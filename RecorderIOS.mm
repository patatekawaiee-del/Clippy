#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#include "Recorder.hpp"

struct Recorder::Impl {
    AVAssetWriter* writer = nil;
    AVAssetWriterInput* input = nil;
    AVAssetWriterInputPixelBufferAdaptor* adaptor = nil;
    int w = 0, h = 0;
    bool recording = false;
};

Recorder::Recorder() : m_impl(new Impl) {}
Recorder::~Recorder() = default;
Recorder& Recorder::get() { static Recorder r; return r; }
bool Recorder::isRecording() const { return m_impl->recording; }

bool Recorder::start(std::string const& path, int w, int h) {
    if (m_impl->recording) finish();
    NSURL* url = [NSURL fileURLWithPath:@(path.c_str())];
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

    NSError* err = nil;
    auto* writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:&err];
    if (!writer) return false;

    NSDictionary* settings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(w), AVVideoHeightKey: @(h),
        AVVideoCompressionPropertiesKey: @{ AVVideoAverageBitRateKey: @(4000000) }
    };
    auto* input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                     outputSettings:settings];
    input.expectsMediaDataInRealTime = YES;

    NSDictionary* attrs = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(w), (id)kCVPixelBufferHeightKey: @(h)
    };
    auto* adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                   sourcePixelBufferAttributes:attrs];
    [writer addInput:input];
    if (![writer startWriting]) return false;
    [writer startSessionAtSourceTime:kCMTimeZero];

    m_impl->writer = writer; m_impl->input = input; m_impl->adaptor = adaptor;
    m_impl->w = w; m_impl->h = h; m_impl->recording = true;
    return true;
}

void Recorder::addFrame(uint8_t const* rgba, double time) {
    if (!m_impl->recording || !m_impl->input.readyForMoreMediaData) return;

    CVPixelBufferRef pb = nullptr;
    if (CVPixelBufferPoolCreatePixelBuffer(nullptr, m_impl->adaptor.pixelBufferPool, &pb) != kCVReturnSuccess)
        return;

    CVPixelBufferLockBaseAddress(pb, 0);
    auto* dst = (uint8_t*)CVPixelBufferGetBaseAddress(pb);
    size_t stride = CVPixelBufferGetBytesPerRow(pb);
    int w = m_impl->w, h = m_impl->h;
    for (int y = 0; y < h; ++y) {
        uint8_t const* s = rgba + (size_t)(h - 1 - y) * w * 4; // flip vertical
        uint8_t* d = dst + y * stride;
        for (int x = 0; x < w; ++x) { // RGBA -> BGRA
            d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; d[3] = 255;
            s += 4; d += 4;
        }
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);

    [m_impl->adaptor appendPixelBuffer:pb withPresentationTime:CMTimeMakeWithSeconds(time, 600)];
    CVPixelBufferRelease(pb);
}

void Recorder::finish() {
    if (!m_impl->recording) return;
    m_impl->recording = false;
    [m_impl->input markAsFinished];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [m_impl->writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    m_impl->writer = nil; m_impl->input = nil; m_impl->adaptor = nil;
}

void Recorder::share(std::string const& path) {
    NSURL* url = [NSURL fileURLWithPath:@(path.c_str())];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* top = UIApplication.sharedApplication.keyWindow.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        auto* vc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        vc.popoverPresentationController.sourceView = top.view; // iPad
        vc.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width / 2, top.view.bounds.size.height / 2, 1, 1);
        [top presentViewController:vc animated:YES completion:nil];
    });
}
