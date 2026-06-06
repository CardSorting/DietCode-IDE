#include "FileWatcher.hpp"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreServices/CoreServices.h>
#include <iostream>

namespace dietcode::filesystem {

struct FileWatcher::Impl {
    std::string rootPath;
    FileEventCallback callback;
    FSEventStreamRef stream{nullptr};
    dispatch_queue_t queue{nullptr};

    static void fsCallback(
        ConstFSEventStreamRef,
        void* clientCallBackInfo,
        size_t numEvents,
        void* eventPaths,
        const FSEventStreamEventFlags eventFlags[],
        const FSEventStreamEventId[]
    ) {
        auto* self = static_cast<Impl*>(clientCallBackInfo);
        const char** paths = static_cast<const char**>(eventPaths);
        
        std::vector<FileEvent> events;
        for (size_t i = 0; i < numEvents; ++i) {
            FileEvent::Kind kind = FileEvent::Kind::Modified;
            
            if (eventFlags[i] & kFSEventStreamEventFlagItemCreated) kind = FileEvent::Kind::Created;
            else if (eventFlags[i] & kFSEventStreamEventFlagItemRemoved) kind = FileEvent::Kind::Deleted;
            else if (eventFlags[i] & kFSEventStreamEventFlagItemRenamed) kind = FileEvent::Kind::Renamed;
            
            events.push_back({kind, paths[i]});
        }
        
        if (!events.empty()) {
            self->callback(events);
        }
    }
};

FileWatcher::FileWatcher(std::string path, FileEventCallback callback)
    : impl_(std::make_unique<Impl>()) {
    impl_->rootPath = std::move(path);
    impl_->callback = std::move(callback);
}

FileWatcher::~FileWatcher() {
    stop();
}

bool FileWatcher::start() {
    if (impl_->stream) return true;

    @autoreleasepool {
        NSString* path = [NSString stringWithUTF8String:impl_->rootPath.c_str()];
        NSArray* pathsToWatch = @[path];
        
        FSEventStreamContext context = {0, impl_.get(), nullptr, nullptr, nullptr};
        
        impl_->queue = dispatch_queue_create("com.dietcode.filewatcher", DISPATCH_QUEUE_SERIAL);
        
        impl_->stream = FSEventStreamCreate(
            nullptr,
            &Impl::fsCallback,
            &context,
            (__bridge CFArrayRef)pathsToWatch,
            kFSEventStreamEventIdSinceNow,
            1.0, // latency
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        );
        
        if (!impl_->stream) return false;
        
        FSEventStreamSetDispatchQueue(impl_->stream, impl_->queue);
        if (!FSEventStreamStart(impl_->stream)) {
            FSEventStreamInvalidate(impl_->stream);
            FSEventStreamRelease(impl_->stream);
            impl_->stream = nullptr;
            return false;
        }
    }
    return true;
}

void FileWatcher::stop() {
    if (impl_->stream) {
        FSEventStreamStop(impl_->stream);
        FSEventStreamInvalidate(impl_->stream);
        FSEventStreamRelease(impl_->stream);
        impl_->stream = nullptr;
    }
    if (impl_->queue) {
        // No need to explicitly release dispatch_queue_t in modern ARC/GCD
        impl_->queue = nullptr;
    }
}

} // namespace dietcode::filesystem
