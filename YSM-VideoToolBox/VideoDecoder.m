//
//  VideoDecoder.m
//  YSM-VideoToolBox
//
//  Created by 忆思梦 on 2017/1/4.
//  Copyright © 2017年 忆思梦. All rights reserved.
//

#import "VideoDecoder.h"

/*
 1>CVPixelBuffer：编码前和解码后的图像数据结构。
 2>CMTime、CMClock和CMTimebase：时间戳相关。时间以64-bit/32-bit的形式出现。
 3>CMBlockBuffer：编码后，结果图像的数据结构。
 4>CMVideoFormatDescription：图像存储方式，编解码器等格式描述。
 5>CMSampleBuffer：存放编解码前后的视频图像的容器数据结构。
 */

/*
 PPS（Picture Parameter Sets）：图像参数集
 SPS（Sequence Parameter Set）：序列参数集
 */

/*
 ________________________________________________
 |startCode | sps | pps |  图像信息(IBP及其他信息)  |
 ￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣￣
 */

const uint8_t startCode[4] = {0,0,0,1};

@interface VideoDecoder ()

//文件输入流
@property (nonatomic, strong) NSInputStream *inputStream;

//解码后的回调
@property (nonatomic, copy) VideoDecodeCompleteBlock completeBlock;

@end

@implementation VideoDecoder{
    //帧
    uint8_t *frame_buffer;
    long frame_size;
    
    //sps
    uint8_t *sps_buffer;
    long sps_size;
    
    //pps
    uint8_t *pps_buffer;
    long pps_size;
    
    uint8_t *_buffer;
    long _bufferSize;
    long _maxSize;
    
    //解码会话
    VTDecompressionSessionRef _decodeSession;
    //描述
    CMFormatDescriptionRef  _formatDescription;
    
}

- (void)decodeWithPath:(NSString *)path complete:(VideoDecodeCompleteBlock)complete{
    self.completeBlock = [complete copy];
    self.inputStream = [NSInputStream inputStreamWithFileAtPath:path];
    [self.inputStream open];
    
    _bufferSize = 0;
    _maxSize = 10000*1000;
    _buffer = malloc(_maxSize);
    
    //循环读取
    while (true) {
        //读数据
        [self readStream];
        
        //转换
        uint32_t nalSize = (uint32_t)(frame_size - 4);
        uint32_t *pNalSize = (uint32_t *)frame_buffer;
        *pNalSize = CFSwapInt32HostToBig(nalSize);
        
        //存放像素信息
        CVPixelBufferRef pixelBuffer = NULL;
        //NAL的类型(startCode后的第一个字节的后5位)
        int NAL_type = frame_buffer[4] & 0x1f;
        switch (NAL_type) {
            case 0x5:
                NSLog(@"Nal type is IDR frame");
                if (!_decodeSession){
                    [self setupDecodeSession];
                }
                pixelBuffer = [self decode];
                break;
            case 0x7:
                NSLog(@"Nal type is SPS");
                //从帧中获取sps信息
                sps_size = frame_size-4;
                if (!sps_buffer){
                    sps_buffer = malloc(sps_size);
                }
                memcpy(sps_buffer, frame_buffer+4, sps_size);
                break;
            case 0x8:
                NSLog(@"Nal type is PPS");
                //从帧中获取sps信息
                pps_size = frame_size-4;
                if (!pps_buffer){
                    pps_buffer = malloc(pps_size);
                }
                memcpy(pps_buffer, frame_buffer+4, pps_size);
                break;
            default:
                //图像信息
                NSLog(@"Nal type is B/P frame or another");
                pixelBuffer = [self decode];
                break;
        }
        if (pixelBuffer) {
            //同步保证数据信息不释放
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (self.completeBlock){
                    self.completeBlock(pixelBuffer);
                }
            });
            CVPixelBufferRelease(pixelBuffer);
        }
        
    }
}

//解码会话
- (void)setupDecodeSession{
    const uint8_t * const paramSetPointers[2] = {sps_buffer,pps_buffer};
    const size_t paramSetSize[2] = {sps_size,pps_size};
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, paramSetPointers, paramSetSize, 4, &_formatDescription);
    
    if (status == noErr){
        CFDictionaryRef attrs = NULL;
        const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
        //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
        //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
        uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
        const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
        attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
        
        //结束后的回调
        VTDecompressionOutputCallbackRecord callBackRecord;
        callBackRecord.decompressionOutputCallback = didDecompress;
        callBackRecord.decompressionOutputRefCon = NULL;
        //填入null，videottoolbox选择解码器
        status = VTDecompressionSessionCreate(kCFAllocatorDefault, _formatDescription, NULL, attrs, &callBackRecord, &_decodeSession);
        
        if (status!=noErr){
            NSLog(@"解码会话创建失败");
        }
        CFRelease(attrs);
    }else {
        NSLog(@"创建FormatDescription失败");
    }
}

- (BOOL)readStream{
    
    if (_bufferSize<_maxSize && self.inputStream.hasBytesAvailable) {
        //正数：读取的字节数，0：读取到尾部，-1：读取错误
        NSInteger readSize = [self.inputStream read:_buffer+_bufferSize maxLength:_maxSize-_bufferSize];
        _bufferSize += readSize;
    }
    //对比buffer的前四位是否是startCode(每一帧前都有startCode)，并且数据长度需要大于startCode
    if (memcmp(_buffer, startCode, 4) == 0 && _bufferSize > 4){
        //buffer的起始和结束位置
        uint8_t *startPoint = _buffer + 4;
        uint8_t *endPoint = _buffer + _bufferSize;
        while (startPoint != endPoint) {
            //获取当前帧长度（通过获取到下一个0x00000001,来确定）
            if (memcmp(startPoint, startCode, 4) == 0){
                //找到下一帧，计算帧长
                frame_size = startPoint - _buffer;
                //置空帧
                if (frame_buffer){
                    free(frame_buffer);
                    frame_buffer = NULL;
                }
                frame_buffer = malloc(frame_size);
                //从缓冲区内复制当前帧长度的信息赋值给帧
                memcpy(frame_buffer, _buffer, frame_size);
                //缓冲区中数据去掉帧数据（长度减少，地址移动）
                memmove(_buffer, _buffer+frame_size, _bufferSize-frame_size);
                _bufferSize -= frame_size;
                
                return YES;
            }else{
                //如果不是，移动指针
                startPoint++;
            }
        }
    }
    return NO;
}

//解码
- (CVPixelBufferRef)decode{
    CVPixelBufferRef outputPixelBuffer = NULL;
    //视频图像数据
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, (void*)frame_buffer, frame_size, kCFAllocatorNull, NULL, 0, frame_size, 0, &blockBuffer);
    if(status == kCMBlockBufferNoErr) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = {frame_size};
        status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, _formatDescription ,  1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
        if (status == kCMBlockBufferNoErr && sampleBuffer) {
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(_decodeSession, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
            
            if(decodeStatus == kVTInvalidSessionErr) {
                NSLog(@"IOS8VT: Invalid session, reset decoder session");
            } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                NSLog(@"IOS8VT: decode failed status=%d(Bad data)", (int)decodeStatus);
            } else if(decodeStatus != noErr) {
                NSLog(@"IOS8VT: decode failed status=%d", (int)decodeStatus);
            }
            
            CFRelease(sampleBuffer);
        }
        CFRelease(blockBuffer);
    }
    free(frame_buffer);
    frame_buffer = NULL;
    return outputPixelBuffer;
}



//解码回调结束 （使用VTDecompressionSessionDecodeFrameWithOutputHandler，直接接受处理结果）
static void didDecompress(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef*)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
}


@end
