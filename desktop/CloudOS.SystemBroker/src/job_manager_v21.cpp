#include "job_manager_v21.h"

#include <algorithm>
#include <chrono>

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
    worker_count = std::max<size_t>(worker_count, 1);
    for (size_t i = 0; i < worker_count; ++i)
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
    }
    cv_.notify_all();

    for (auto& w : workers_)
    {
        if (w.joinable())
        {
            w.join();
        }
    }
    workers_.clear();
}

std::string JobManagerV21::SubmitJob(const std::string& type, JobFunction func)
{
    if (!func) return {};

    std::string job_id = "job-" + std::to_string(next_job_id_++);
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
    JsonObject payload;
    bool cancelled = false;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = jobs_.find(job_id);
        if (it == jobs_.end()) return false;

        auto& job = it->second;
        if (job->info.state != JobState::Queued && job->info.state != JobState::Running)
        {
            return false;
        }

        job->cancel_flag.store(true);
        job->info.state = JobState::Cancelled;
        job->info.updated_at_ms = NowMs();

        payload["jobId"] = JsonValue(job_id);
        payload["state"] = JsonValue(JobStateToString(JobState::Cancelled));
        cancelled = true;
    }

    if (cancelled)
    {
        EventBusV21::Instance().Publish("job.cancelled", payload);
    }
    return cancelled;
}

bool JobManagerV21::GetJobInfo(const std::string& job_id, JobInfo& info) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = jobs_.find(job_id);
    if (it != jobs_.end())
    {
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
        if (v->info.state == JobState::Queued || v->info.state == JobState::Running)
        {
            active++;
        }
    }
    return active;
}

void JobManagerV21::Reset()
{
    std::lock_guard<std::mutex> lock(mutex_);
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
            cv_.wait(lock, [this]() {
                return !running_.load() || !queue_.empty();
            });

            if (!running_.load()) break;

            if (!queue_.empty())
            {
                const std::string job_id = queue_.front();
                queue_.erase(queue_.begin());
                auto it = jobs_.find(job_id);
                if (it != jobs_.end())
                {
                    job = it->second;
                    if (!job->cancel_flag.load() && job->info.state == JobState::Queued)
                    {
                        job->info.state = JobState::Running;
                        job->info.updated_at_ms = NowMs();
                    }
                }
            }
        }

        if (!job || job->cancel_flag.load()) continue;

        auto progress_cb = [this, job](double p) {
            JsonObject payload;
            bool publish = false;
            const double bounded = std::clamp(p, 0.0, 1.0);

            {
                std::lock_guard<std::mutex> lock(mutex_);
                if (!job->cancel_flag.load() && job->info.state == JobState::Running)
                {
                    job->info.progress = bounded;
                    job->info.updated_at_ms = NowMs();
                    payload["jobId"] = JsonValue(job->info.id);
                    payload["progress"] = JsonValue(bounded);
                    payload["state"] = JsonValue(JobStateToString(JobState::Running));
                    publish = true;
                }
            }

            if (publish)
            {
                EventBusV21::Instance().Publish("job.progress", payload);
            }
        };

        std::string err;
        bool ok = false;
        if (job->func)
        {
            ok = job->func(job->cancel_flag, progress_cb, err);
        }

        JsonObject payload;
        std::string event_name;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (job->cancel_flag.load())
            {
                // CancelJob already transitions the state and publishes the
                // cancellation event. Keep the worker from overwriting it.
                if (job->info.state != JobState::Cancelled)
                {
                    job->info.state = JobState::Cancelled;
                    job->info.updated_at_ms = NowMs();
                    payload["jobId"] = JsonValue(job->info.id);
                    payload["state"] = JsonValue(JobStateToString(JobState::Cancelled));
                    event_name = "job.cancelled";
                }
            }
            else if (ok)
            {
                job->info.state = JobState::Completed;
                job->info.progress = 1.0;
                job->info.updated_at_ms = NowMs();
                payload["jobId"] = JsonValue(job->info.id);
                payload["state"] = JsonValue(JobStateToString(JobState::Completed));
                event_name = "job.completed";
            }
            else
            {
                job->info.state = JobState::Failed;
                job->info.error_message = err;
                job->info.updated_at_ms = NowMs();
                payload["jobId"] = JsonValue(job->info.id);
                payload["error"] = JsonValue(err);
                payload["state"] = JsonValue(JobStateToString(JobState::Failed));
                event_name = "job.failed";
            }
        }

        if (!event_name.empty())
        {
            EventBusV21::Instance().Publish(event_name, payload);
        }
    }
}

} // namespace CloudOS
