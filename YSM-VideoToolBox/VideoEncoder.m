//
//  VideoEncoder.m
//  YSM-VideoToolBox
//
//  Created by 忆思梦 on 2017/1/3.
//  Copyright © 2017年 忆思梦. All rights reserved.
//

#import "VideoEncoder.h"

void didFinishedCompression(void * CM_NULLABLE outputCallbackRefCon, void * CM_NULLABLE sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CM_NULLABLE CMSampleBufferRef sampleBuffer);

@interface VideoEncoder ()

//文件写入对象
@property (nonatomic, strong) NSFileHandle *fileHandle;

//压缩编码会话
@property (nonatomic, assign) VTCompressionSessionRef compressionSession;

//当前帧数
@property (nonatomic, assign) NSInteger currentFrame;

@end

/*
 H264编码分为两层:  
    1>视频编码层（VCL：Video Coding Layer）负责高效的视频内容表示
    2>网络提取层（NAL：Network Abstraction Layer）负责以网络所要求的恰当的方式对数据进行打包和传送(根据不同的网络把数据打包成相应的格式，将VCL产生的比特字符串适配到各种各样的网络和多元环境中)
 
 NALU：NAL unit,NAL单元
 
 I帧、P帧、B帧都是被封装成一个或者多个NALU进行传输或者存储的
 I帧开始之前也有非VCL的NAL单元，用于保存其他信息，比如：PPS、SPS
 PPS（Picture Parameter Sets）：图像参数集
 SPS（Sequence Parameter Set）：序列参数集
 在实际的H264数据帧中，往往帧前面带有00 00 00 01 或 00 00 01分隔符，一般来说编码器编出的首帧数据为PPS与SPS，接着为I帧，后续是B帧、P帧等数据
 */

@implementation VideoEncoder

- (instancetype)init{
    if (self = [super init]) {
        //1、初始化文件写入对象
        [self setupFileHandle];
        
        //2、初始化压缩编码会话
        [self setupCompressionSession];
    }
    return self;
}

- (void)setupFileHandle{
    //1、创建存储路径
    NSString * filePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true).lastObject stringByAppendingPathComponent:@"videoToolBox.h264"];
    //2、检查文件是否存在
    NSFileManager * fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filePath]) {
        //3、创建文件
        [fileManager createFileAtPath:filePath contents:nil attributes:nil];
    }
    //4、创建写入对象
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    
    //5、移动到文件的末尾继续写入
    [self.fileHandle seekToEndOfFile];
}

- (void)setupCompressionSession{
    //1、设置当前帧为0
    self.currentFrame = 0;
    
    //2、录制视频宽高
    int width = [UIScreen mainScreen].bounds.size.width;
    int height = [UIScreen mainScreen].bounds.size.height;

    /**
     3、创建压缩编码会话,用于画面编码

     @param NULL 会话的分配器。 传递NULL以使用默认分配器。
     @param width <#width description#>
     @param height <#height description#>
     @param kCMVideoCodecType_H264 编码类型
     @param NULL 指定必须使用的特定视频编码器。传递NULL，让视频工具箱选择一个编码器。
     @param NULL <#NULL description#>
     @param NULL <#NULL description#>
     @param didCompression <#didCompression description#>
     @param void <#void description#>
     @return <#return value description#>
     */
    VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didFinishedCompression, (__bridge void *)(self), &_compressionSession);
    
    //4、设置实时编码输出
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    
    //5、设置帧率(每秒多少帧,如果帧率过低,会造成画面卡顿，大于16，人眼就识别不出来了)
    int fps = 30;
    CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
    
    //6、设置码率(码率: 编码效率, 码率越高,则画面越清晰, 如果码率较低会引起马赛克 --> 码率高有利于还原原始画面,但是也不利于传输)
    int bitRate = 800*1024;
    CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bitRate);
    //平均码率
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
    NSArray * limits = @[@(bitRate*1.5/8),@1];
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFTypeRef _Nonnull)(limits));
    
    //7、设置关键帧间隔
    int frameInterval = 30;
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
 
    // 8.基本设置结束, 准备进行编码
    VTCompressionSessionPrepareToEncodeFrames(self.compressionSession);
}

/**
 关键帧，处理sps和pps
 
 @param sampleBuffer <#sampleBuffer description#>
 */
- (void)handleKeyframeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    NSLog(@"关键帧");
    //获取编码后的信息（存储于CMFormatDescriptionRef中）
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    // 获取SPS信息
    size_t sparameterSetSize, sparameterSetCount;
    const uint8_t *sparameterSet;
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
    
    // 获取PPS信息
    size_t pparameterSetSize, pparameterSetCount;
    const uint8_t *pparameterSet;
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
    
    // 将sps和pps转成NSData
    NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
    NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
    
    // 写入文件
    [self writeSps:sps pps:pps];
}


/**
 处理图像数据区域
 
 @param sampleBuffer <#sampleBuffer description#>
 */
- (void)handleImageDataBuffer:(CMSampleBufferRef)sampleBuffer{
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        size_t bufferOffset = 0;
        // 返回的NALU数据前四个字节不是0001的startcode，而是帧长度length
        static const int AVCCHeaderLength = 4;
        /*
         //前四个字节存放内容查看
         NSData * redata = [[NSData alloc] initWithBytes:dataPointer length:AVCCHeaderLength];
         int result = 0;
         [redata getBytes:&result length:4];
         NSLog(@"前四个字节：%d",result);
         */
        
        // 循环读取NALU数据(通过指针偏移读取)
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            //NAL unit的内存起始位置
            char *startPointer = dataPointer + bufferOffset;
            
            // 读取NAL单元的长度
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, startPointer, AVCCHeaderLength);
            
            //host Big－endian
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            //读取到数据
            NSData* data = [[NSData alloc] initWithBytes:(startPointer + AVCCHeaderLength) length:NALUnitLength];
            
            //对数据进行编码
            [self encodeImageData:data];
            
            // 修改指针偏移量到下一个NAL unit区域
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
    }
}

//将sps和pps写入文件
- (void)writeSps:(NSData*)sps pps:(NSData*)pps{
    // 1.拼接NALU的header
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *ByteHeader = [NSData dataWithBytes:bytes length:length];
    
    // 2.将NALU的头&NALU的体写入文件
    [self.fileHandle writeData:ByteHeader];
    [self.fileHandle writeData:sps];
    [self.fileHandle writeData:ByteHeader];
    [self.fileHandle writeData:pps];
}

//视频数据编码写入文件
- (void)encodeImageData:(NSData*)data{
//    NSLog(@"encodedData %d", (int)[data length]);
    if (self.fileHandle != NULL){
        //帧头
        const char bytes[] = "\x00\x00\x00\x01";
        //字符串有隐式结尾"\0"
        size_t length = (sizeof bytes) - 1;
        NSData *header = [NSData dataWithBytes:bytes length:length];
        [self.fileHandle writeData:header];
        [self.fileHandle writeData:data];
    }
}

//编码
- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    // 1.将sampleBuffer转成imageBuffer
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 2.根据当前的帧数,创建CMTime的时间
    CMTime presentationTimeStamp = CMTimeMake(self.currentFrame++, 1000);
    
    // 3.开始编码当前帧
        //有关编码操作的信息（例如：正在进行，帧被丢弃等）
    VTEncodeInfoFlags flags;
    OSStatus statusCode = VTCompressionSessionEncodeFrame(self.compressionSession, imageBuffer, presentationTimeStamp, kCMTimeInvalid, NULL, (__bridge void * _Nullable)(self), &flags);
    if (statusCode == noErr) {
        NSLog(@"H264: VTCompressionSessionEncodeFrame Success");
    }
}

//停止编码
- (void)endEncode{
    VTCompressionSessionCompleteFrames(self.compressionSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(self.compressionSession);
    if (self.compressionSession){
        CFRelease(self.compressionSession);
        self.compressionSession = NULL;
    }
}

@end

//完成压缩回调
void didFinishedCompression(void * CM_NULLABLE outputCallbackRefCon, void * CM_NULLABLE sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CM_NULLABLE CMSampleBufferRef sampleBuffer ){
    
    // 1.判断状态是否等于没有错误
    if (status != noErr) {
        return;
    }
    // 2.根据传入的参数获取对象
    VideoEncoder* encoder = (__bridge VideoEncoder*)outputCallbackRefCon;
    
    // 3.判断是否是关键帧
    bool isKeyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    // 3.1 如果是关键帧，需要先写入sps和pps
    if (isKeyframe){
        [encoder handleKeyframeSampleBuffer:sampleBuffer];
    }
    
    // 4.获取图像数据区域块
    [encoder handleImageDataBuffer:sampleBuffer];
}

