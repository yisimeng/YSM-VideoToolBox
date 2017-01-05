//
//  ViewController.m
//  YSM-VideoToolBox
//
//  Created by 忆思梦 on 2017/1/3.
//  Copyright © 2017年 忆思梦. All rights reserved.
//

#import "ViewController.h"
#import "VideoCapture.h"
#import <GLKit/GLKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import "VideoDecoder.h"
@interface ViewController ()

//捕捉对象
@property (nonatomic, strong) VideoCapture *capture;

@property (nonatomic, strong) EAGLContext *glContext;
@property (nonatomic, strong) GLKView *glView;
@property (nonatomic, strong) CIContext *ciContext;

@property (nonatomic, strong) VideoDecoder *videoDecoder;

@end

@implementation ViewController{
    uint8_t buffer;
    NSUInteger length;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.capture = [[VideoCapture alloc] init];
}
- (IBAction)play:(id)sender {
    self.videoDecoder = [[VideoDecoder alloc] init];
    self.glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    self.glView = [[GLKView alloc] initWithFrame:self.view.bounds context:self.glContext];
    self.glView.frame = self.view.bounds;
    self.ciContext = [CIContext contextWithEAGLContext:self.glContext];
    [self.view insertSubview:self.glView atIndex:0];
    
    [self decode];
}

- (IBAction)start:(id)sender {
    [self.capture startCaptureWithPreView:self.view];
}

- (IBAction)stop:(id)sender {
    [self.capture stopCapture];
}

- (void)decode{
//    NSString * path = [[NSBundle mainBundle] pathForResource:@"videoToolBox" ofType:@"h264"];
    
    NSString * path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true).lastObject stringByAppendingPathComponent:@"videoToolBox.h264"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [_videoDecoder decodeWithPath:path complete:^(CVPixelBufferRef pixelBuffer) {
            @autoreleasepool {
                CIImage * ciimage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
                if (_glContext != [EAGLContext currentContext]){
                    [EAGLContext setCurrentContext:_glContext];
                }
                [_glView bindDrawable];
                [_ciContext drawImage:ciimage inRect:CGRectMake(0, 0, _glView.bounds.size.width*2, _glView.bounds.size.height*2) fromRect:ciimage.extent];
                [_glView display];
            }
        }];
    });
}

@end
