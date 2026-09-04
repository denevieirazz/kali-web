#pragma once

#include "event_bus_v21.h"
#include "protocol_v21.h"

#include <atomic>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace CloudOS
{

enum class JobState
{
    Queued,
    Running,
    Completed,
    Failed,
    Cancelled
};

std::string JobStateToString(JobState s);

struct JobInfo final
{
    std::string id;
    std::string type;
    JobState state{JobState::Queued};
    double progress{0.0};
    std::string error_message;
    uint64_t created_at_ms{0};
    uint64_t updated_at_ms{0};
};

using JobFunction = std::function<bool(std::atomic_bool& cancel_flag, std::function<void(double)> progress_cb, std::string& err)>;

class JobManagerV21 final
{
public:
    static JobManagerV21& Instance();

    JobManagerV21(const JobManagerV21&) = delete;
    JobManagerV21& operator=(const JobManagerV21&) = delete;

    void Initialize(size_t worker_count = 2);
    void Shutdown();

    // Returns an empty string if the manager is stopped or the bounded queue
    // cannot accept another job.
    std::string SubmitJob(const std::string& type, JobFunction func);
    bool CancelJob(const std::string& job_id);

    bool GetJobInfo(const std::string& job_id, JobInfo& info) const;
    std::vector<JobInfo> ListJobs() const;
    size_t GetActiveJobCount() const;

    void Reset(); // For testing

private:
    JobManagerV21() = default;
    ~JobManagerV21();

    void WorkerLoop();

    struct InternalJob final
    {
        mutable std::mutex info_mutex;
        JobInfo info;
        JobFunction func;
        std::atomic_bool cancel_flag{false};
    };

    mutable std::mutex mutex_;
    std::condition_variable cv_;
    std::unordered_map<std::string, std::shared_ptr<InternalJob>> jobs_;
    std::vector<std::string> queue_;
    std::vector<std::thread> workers_;
    std::atomic_bool running_{false};
    std::atomic_uint64_t next_job_id_{1};

    static constexpr size_t kMaxRetainedJobs = 512;
    static constexpr size_t kMaxQueuedJobs = 256;
};

} // namespace CloudOS
