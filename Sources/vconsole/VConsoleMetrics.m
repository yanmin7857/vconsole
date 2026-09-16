#import "VConsoleMetrics.h"
#import <mach/mach.h>
#import <mach/thread_info.h>

double VConsoleAppCPUUsage(void) {
    kern_return_t kr;
    thread_array_t threads = NULL;
    mach_msg_type_number_t tcount = 0;
    kr = task_threads(mach_task_self(), &threads, &tcount);
    if (kr != KERN_SUCCESS) return -1.0;
    double total = 0.0;
    for (mach_msg_type_number_t i = 0; i < tcount; i++) {
        thread_info_data_t tinfo;
        mach_msg_type_number_t count = THREAD_INFO_MAX;
        kr = thread_info(threads[i], THREAD_BASIC_INFO, (thread_info_t)tinfo, &count);
        if (kr == KERN_SUCCESS) {
            thread_basic_info_t basic = (thread_basic_info_t)tinfo;
            // 跳过 idle 线程，否则 CPU 占用被凭空拉高
            if ((basic->flags & TH_FLAGS_IDLE) == 0) {
                total += basic->cpu_usage / (double)TH_USAGE_SCALE;
            }
        }
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads, tcount * sizeof(thread_t));
    return total * 100.0;
}

double VConsoleAppMemoryMB(void) {
    task_basic_info_data_t info;
    mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
    kern_return_t kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count);
    if (kr != KERN_SUCCESS) return -1.0;
    return (double)info.resident_size / (1024.0 * 1024.0);
}

NSString *VConsoleFormatBytes(long long bytes) {
    if (bytes < 0) bytes = 0;
    if (bytes < 1024LL) return [NSString stringWithFormat:@"%lld B", bytes];
    double kb = bytes / 1024.0;
    if (kb < 1024.0) return [NSString stringWithFormat:@"%.1f KB", kb];
    double mb = kb / 1024.0;
    if (mb < 1024.0) return [NSString stringWithFormat:@"%.1f MB", mb];
    return [NSString stringWithFormat:@"%.2f GB", mb / 1024.0];
}

NSString *VConsoleFormatPercent(double percent) {
    return [NSString stringWithFormat:@"%.1f%%", percent];
}
