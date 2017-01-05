//
//  VideoCapture.m
//  YSM-VideoToolBox
//
//  Created by 忆思梦 on 2017/1/3.
//  Copyright © 2017年 忆思梦. All rights reserved.
//

#import "VideoCapture.h"
#import <AVFoundation/AVFoundation.h>
#import "VideoEncoder.h"

@interface VideoCapture ()<AVCaptureVideoDataOutputSampleBufferDelegate>

//会话捕捉
@property (nonatomic, strong) AVCaptureSession *session;
//预览图层
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *layer;

//编码对象
@property (nonatomic, strong) VideoEncoder *videoEncoder;

@end

@implementation VideoCapture

- (void)startCaptureWithPreView:(UIView *)preView{
    
    //初始化编码对象
    self.videoEncoder = [[VideoEncoder alloc] init];
    
    //1、创建会话捕捉
    self.session = [[AVCaptureSession alloc] init];
    
    //2、设置输入输出
    AVCaptureDevice * device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError * error = nil;
    AVCaptureDeviceInput * videoInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    [self.session addInput:videoInput];
    
    AVCaptureVideoDataOutput * output = [[AVCaptureVideoDataOutput alloc] init];
    [output setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    [self.session addOutput:output];
    
    //3、设置录制方向
    AVCaptureConnection * connection = [output connectionWithMediaType:AVMediaTypeVideo];
    [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    //4、设置预览图层
    self.layer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    self.layer.frame = preView.bounds;
    [preView.layer insertSublayer:self.layer atIndex:0];
    
    //5、开始捕捉
    [self.session startRunning];
}

- (void)stopCapture{
    [self.session stopRunning];
    [self.layer removeFromSuperlayer];
    [self.videoEncoder endEncode];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    
    [self.videoEncoder encodeSampleBuffer:sampleBuffer];
}

@end
