#include "job_manager_v21.h"

#include <algorithm>
#include <chrono>
#include <cmath>

namespace CloudOS
{

namespace
{
uint64_t NowMs()
{
    return static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count());
}
} // namespace

std::string JobStateToString(JobState s)
{
    switch (s)
    {
    case JobState::Queued: return "queued";
    case JobState::Running: return "running";
    case JobState::Completed: return "completed";
    case JobState::Failed: return "failed";
    case JobState::Cancelled: return "cancelled";
    default: return "unknown";
    }
}

JobManagerV21& JobManagerV21::Instance()
{
    static JobManagerV21 instance;
    return instance;
}

JobManagerV21::~JobManagerV21()
{
    Shutdown();
}

void JobManagerV21::Initialize(size_t worker_count)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (running_.load()) return;

    running_.store(true);
    workers_.clear();
    const size_t bounded_workers = std::clamp<size_t>(worker_count, 1, 16);
    for (size_t i = 0; i < bounded_workers; ++i)
    {
        workers_.emplace_back(&JobManagerV21::WorkerLoop, this);
    }
}

void JobManagerV21::Shutdown()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_.load()) return;
        running_.store(false);
        for (auto& [id, job] : jobs_)
        {
            (void)id;
            job->cancel_flag.store(true);
        }
    }
    cv_.notify_all();

    for (auto& w : workers_)
    {
        if (w.joinable()) w.join();
    }
    workers_.clear();
}

std::string JobManagerV21::SubmitJob(const std::string& type, JobFunction func)
{
    if (type.empty() || !func || !running_.load()) return {};

    const std::string job_id = "job-" + std::to_string(next_job_id_++);
    auto job = std::make_shared<InternalJob>();
    job->info.id = job_id;
    job->info.type = type;
    job->info.state = JobState::Queued;
    job->info.progress = 0.0;
    job->info.created_at_ms = NowMs();
    job->info.updated_at_ms = job->info.created_at_ms;
    job->func = std::move(func);

    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_.load()) return {};

        if (jobs_.size() >= kMaxRetainedJobs)
        {
            for (auto it = jobs_.begin(); it != jobs_.end() && jobs_.size() >= kMaxRetainedJobs;)
            {
                std::lock_guard<std::mutex> info_lock(it->second->info_mutex);
                const JobState state = it->second->info.state;
                if (state == JobState::Completed || state == JobState::Failed || state == JobState::Cancelled)
                {
                    it = jobs_.erase(it);
                }
                else
                {
                    ++it;
                }
            }
        }

        if (jobs_.size() >= kMaxRetainedJobs || queue_.size() >= kMaxQueuedJobs)
        {
            return {};
        }

        jobs_[job_id] = job;
        queue_.push_back(job_id);
    }
    cv_.notify_one();

    JsonObject payload;
    payload["jobId"] = JsonValue(job_id);
    payload["type"] = JsonValue(type);
    payload["state"] = JsonValue(JobStateToString(JobState::Queued));
    EventBusV21::Instance().Publish("job.started", payload);

    return job_id;
}

bool JobManagerV21::CancelJob(const std::string& job_id)
{
    std::shared_ptr<InternalJob> job;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto it = jobs_.find(job_id);
        if (it == jobs_.end()) return false;
        job = it->second;
    }

    JobInfo cancelled_info;
    {
        std::lock_guard<std::mutex> info_lock(job->info_mutex);
        if (job->info.state != JobState::Queued && job->info.state != JobState::Running)
        {
            return false;
        }

        job->cancel_flag.store(true);
        job->info.state = JobState::Cancelled;
        job->info.error_message = "cancelled";
        job->info.updated_at_ms = NowMs();
        cancelled_info = job->info;
    }

    JsonObject payload;
    payload["jobId"] = JsonValue(job_id);
    payload["state"] = JsonValue(JobStateToString(cancelled_info.state));
    EventBusV21::Instance().Publish("job.cancelled", payload);
    return true;
}

bool JobManagerV21::GetJobInfo(const std::string& job_id, JobInfo& info) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = jobs_.find(job_id);
    if (it != jobs_.end())
    {
        std::lock_guard<std::mutex> info_lock(it->second->info_mutex);
        info = it->second->info;
        return true;
    }
    return false;
}

std::vector<JobInfo> JobManagerV21::ListJobs() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    std::vector<JobInfo> list;
    list.reserve(jobs_.size());
    for (const auto& [k, v] : jobs_)
    {
        (void)k;
        std::lock_guard<std::mutex> info_lock(v->info_mutex);
        list.push_back(v->info);
    }
    return list;
}

size_t JobManagerV21::GetActiveJobCount() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    size_t active = 0;
    for (const auto& [k, v] : jobs_)
    {
        (void)k;
        std::lock_guard<std::mutex> info_lock(v->info_mutex);
        if (v->info.state == JobState::Queued || v->info.state == JobState::Running) ++active;
    }
    return active;
}

void JobManagerV21::Reset()
{
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& [id, job] : jobs_)
    {
        (void)id;
        job->cancel_flag.store(true);
    }
    jobs_.clear();
    queue_.clear();
}

void JobManagerV21::WorkerLoop()
{
    while (true)
    {
        std::shared_ptr<InternalJob> job;
        {
            std::unique_lock<std::mutex> lock(mutex_);
            cv_.wait(lock, [this]() { return !running_.load() || !queue_.empty(); });
            if (!running_.load()) break;

            if (!queue_.empty())
            {
                const std::string job_id = queue_.front();
                queue_.erase(queue_.begin());
                const auto it = jobs_.find(job_id);
                if (it != jobs_.end()) job = it->second;
            }
        }

        if (!job) continue;
        if (job->cancel_flag.load()) continue;

        {
            std::lock_guard<std::mutex> info_lock(job->info_mutex);
            if (job->info.state == JobState::Cancelled) continue;
            job->info.state = JobState::Running;
            job->info.updated_at_ms = NowMs();
        }

        auto progress_cb = [job](double p) {
            if (!std::isfinite(p)) return;
            JobInfo current;
            {
                std::lock_guard<std::mutex> info_lock(job->info_mutex);
                if (job->info.state == JobState::Cancelled) return;
                job->info.progress = std::clamp(p, 0.0, 100.0);
                job->info.updated_at_ms = NowMs();
                current = job->info;
            }
            JsonObject payload;
            payload["jobId"] = JsonValue(current.id);
            payload["progress"] = JsonValue(current.progress);
            payload["state"] = JsonValue(JobStateToString(JobState::Running));
            EventBusV21::Instance().Publish("job.progress", payload);
        };

        std::string err;
        bool ok = false;
        try
        {
            ok = job->func(job->cancel_flag, progress_cb, err);
        }
        catch (...)
        {
            ok = false;
            err = "unhandled_job_exception";
        }

        JobInfo final_info;
        {
            std::lock_guard<std::mutex> info_lock(job->info_mutex);
            if (job->cancel_flag.load() || job->info.state == JobState::Cancelled)
            {
                job->info.state = JobState::Cancelled;
                if (job->info.error_message.empty()) job->info.error_message = "cancelled";
            }
            else if (ok)
            {
                job->info.state = JobState::Completed;
                job->info.progress = 100.0;
            }
            else
            {
                job->info.state = JobState::Failed;
                job->info.error_message = err.empty() ? "job_failed" : err;
            }
            job->info.updated_at_ms = NowMs();
            final_info = job->info;
        }

        JsonObject payload;
        payload["jobId"] = JsonValue(final_info.id);
        payload["state"] = JsonValue(JobStateToString(final_info.state));
        if (final_info.state == JobState::Completed)
        {
            EventBusV21::Instance().Publish("job.completed", payload);
        }
        else if (final_info.state == JobState::Failed)
        {
            payload["error"] = JsonValue(final_info.error_message);
            EventBusV21::Instance().Publish("job.failed", payload);
        }
    }
}

} // namespace CloudOS
