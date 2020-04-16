#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import "vector"

#import "EmbeddedShader.h"
#import "EmbeddedJPEG.h"

id<MTLLibrary> decodeMTLLibrary(id<MTLDevice> device, const void *bytes, int length) {
    __block id<MTLLibrary> metallib = nil;
    __block NSError *error = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    dispatch_data_t lib = dispatch_data_create(bytes,length,nil,DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    dispatch_data_apply(lib,^bool (dispatch_data_t _Nonnull region, size_t offset, const void * _Nonnull buffer, size_t size) {
        metallib = [device newLibraryWithData:region error:&error];
        dispatch_semaphore_signal(semaphore);
        return true;
    });
    dispatch_semaphore_wait(semaphore,DISPATCH_TIME_FOREVER);
    if(error==nil&&metallib) return metallib;
    return nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcomma"
#pragma clang diagnostic ignored "-Wunused-function"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
namespace stb_image {
    #import "stb_image.h"
}
#pragma clang diagnostic pop

const unsigned char *decodeJPEG(const unsigned char *bytes, int length, int *w, int *h, int bpp=4) {
    int _bpp = 0;
    return (const unsigned char *)stb_image::stbi_load_from_memory(bytes,length,w,h,&_bpp,bpp);	
}


namespace Plane {
    
    static const int VERTICES_SIZE = 4;
    static const float vertices[VERTICES_SIZE][4] = {
        { -1.f,-1.f, 0.f, 1.f },
        {  1.f,-1.f, 0.f, 1.f },
        {  1.f, 1.f, 0.f, 1.f },
        { -1.f, 1.f, 0.f, 1.f }
    };
    
    static const int INDICES_SIZE = 6;
    static const unsigned short indices[INDICES_SIZE] = {
        0,1,2,
        0,2,3
    };

    static const int TEXCOORD_SIZE = 4;
    static const float texcoord[TEXCOORD_SIZE][2] = {
        { 0.f, 0.f },
        { 1.f, 0.f },
        { 1.f, 1.f },
        { 0.f, 1.f }
    };
}

class MetalLayer {
    
    protected:
        
        CAMetalLayer *_metalLayer;
        MTLRenderPassDescriptor *_renderPassDescriptor;
        
        id<MTLDevice> _device;
        id<MTLCommandQueue> _commandQueue;
        
        id<CAMetalDrawable> _metalDrawable;
        
        id<MTLTexture> _drawabletexture;    		
            
        id<MTLBuffer> _verticesBuffer;
        id<MTLBuffer> _indicesBuffer;
        
        std::vector<id<MTLLibrary>> _library;
        std::vector<id<MTLRenderPipelineState>> _renderPipelineState;
        std::vector<MTLRenderPipelineDescriptor *> _renderPipelineDescriptor;
        std::vector<id<MTLArgumentEncoder>> _argumentEncoder;
        
        id<MTLTexture> _texture;
        id<MTLBuffer> _texcoordBuffer;

        std::vector<id<MTLBuffer>> _argumentEncoderBuffer;
                        
        int _width;
        int _height;
        CGRect _frame;
        
        void setColorAttachment(MTLRenderPipelineColorAttachmentDescriptor *colorAttachment) {
            colorAttachment.blendingEnabled = YES;
            colorAttachment.rgbBlendOperation = MTLBlendOperationAdd;
            colorAttachment.alphaBlendOperation = MTLBlendOperationAdd;
            colorAttachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            colorAttachment.sourceAlphaBlendFactor = MTLBlendFactorOne;
            colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOne;
        }

        virtual bool setupShader() {
            for(int k=0; k<this->_library.size(); k++) {
                id<MTLFunction> vertexFunction = [this->_library[k] newFunctionWithName:@"vertexShader"];
                if(!vertexFunction) return nil;
                id<MTLFunction> fragmentFunction = [this->_library[k] newFunctionWithName:@"fragmentShader"];
                if(!fragmentFunction) return nil;
                this->_renderPipelineDescriptor.push_back([MTLRenderPipelineDescriptor new]);
                if(!this->_renderPipelineDescriptor[k]) return nil;
                this->_argumentEncoder.push_back([fragmentFunction newArgumentEncoderWithBufferIndex:0]);
                this->_renderPipelineDescriptor[k].depthAttachmentPixelFormat      = MTLPixelFormatInvalid;
                this->_renderPipelineDescriptor[k].stencilAttachmentPixelFormat    = MTLPixelFormatInvalid;
                this->_renderPipelineDescriptor[k].colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                this->setColorAttachment(this->_renderPipelineDescriptor[k].colorAttachments[0]);
                this->_renderPipelineDescriptor[k].sampleCount = 1;
                this->_renderPipelineDescriptor[k].vertexFunction   = vertexFunction;
                this->_renderPipelineDescriptor[k].fragmentFunction = fragmentFunction;	
                NSError *error = nil;
                this->_renderPipelineState.push_back([this->_device newRenderPipelineStateWithDescriptor:this->_renderPipelineDescriptor[k] error:&error]);
                if(error||!this->_renderPipelineState[k]) return true;
            }
            return false;
        }
        
        virtual bool updateShader(unsigned int index) {
            if(index>=this->_library.size()) return true;
            id<MTLFunction> vertexFunction = [this->_library[index] newFunctionWithName:@"vertexShader"];
            if(!vertexFunction) return nil;
            id<MTLFunction> fragmentFunction = [this->_library[index] newFunctionWithName:@"fragmentShader"];
            if(!fragmentFunction) return nil;
            this->_argumentEncoder[index] = [fragmentFunction newArgumentEncoderWithBufferIndex:0];			
            this->_renderPipelineDescriptor[index].sampleCount = 1;
            this->_renderPipelineDescriptor[index].vertexFunction   = vertexFunction;
            this->_renderPipelineDescriptor[index].fragmentFunction = fragmentFunction;
            NSError *error = nil;
            this->_renderPipelineState[index] = [this->_device newRenderPipelineStateWithDescriptor:this->_renderPipelineDescriptor[index] error:&error];
            if(error||!this->_renderPipelineState[index]) return true;
            return false;
        }
        
    public:
        
        MetalLayer() {}
        ~MetalLayer() {}
        
        id<MTLTexture> texture() { 
            return this->_texture; 
        }
        
        bool setup() {
            
            MTLTextureDescriptor *texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:this->_width height:this->_height mipmapped:NO];
            if(!texDesc) return false;
                
            this->_texture = [_device newTextureWithDescriptor:texDesc];
            if(!this->_texture) return false;
                
            this->_verticesBuffer = [this->_device newBufferWithBytes:Plane::vertices length:Plane::VERTICES_SIZE*sizeof(float)*4 options:MTLResourceOptionCPUCacheModeDefault];
            if(!this->_verticesBuffer) return false;
            
            this->_indicesBuffer = [this->_device newBufferWithBytes:Plane::indices length:Plane::INDICES_SIZE*sizeof(short) options:MTLResourceOptionCPUCacheModeDefault];
            if(!this->_indicesBuffer) return false;			
            
            this->_texcoordBuffer = [this->_device newBufferWithBytes:Plane::texcoord length:Plane::TEXCOORD_SIZE*sizeof(float)*2 options:MTLResourceOptionCPUCacheModeDefault];
            if(!this->_texcoordBuffer) return false;
                
            for(int k=0; k<this->_library.size(); k++) {
                this->_argumentEncoderBuffer.push_back([this->_device newBufferWithLength:sizeof(float)*[this->_argumentEncoder[k] encodedLength] options:MTLResourceOptionCPUCacheModeDefault]);

                [this->_argumentEncoder[k] setArgumentBuffer:this->_argumentEncoderBuffer[k] offset:0];
                [this->_argumentEncoder[k] setTexture:this->_texture atIndex:0];
            }
                            
            return true;
        } 
        
        id<MTLCommandBuffer> setupCommandBuffer() {
            id<MTLCommandBuffer> commandBuffer = [this->_commandQueue commandBuffer];
            MTLRenderPassColorAttachmentDescriptor *colorAttachment = this->_renderPassDescriptor.colorAttachments[0];
            colorAttachment.texture = this->_metalDrawable.texture;
            colorAttachment.loadAction  = MTLLoadActionClear;
            colorAttachment.clearColor  = MTLClearColorMake(0.0f,0.0f,0.0f,0.0f);
            colorAttachment.storeAction = MTLStoreActionStore;
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:this->_renderPassDescriptor];
            [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [renderEncoder setRenderPipelineState:this->_renderPipelineState[0]];
            [renderEncoder setVertexBuffer:this->_verticesBuffer offset:0 atIndex:0];
            [renderEncoder setVertexBuffer:this->_texcoordBuffer offset:0 atIndex:1];
            
            [renderEncoder useResource:this->_texture usage:MTLResourceUsageSample];
            [renderEncoder setFragmentBuffer:this->_argumentEncoderBuffer[0] offset:0 atIndex:0];
            
            [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:Plane::INDICES_SIZE indexType:MTLIndexTypeUInt16 indexBuffer:this->_indicesBuffer indexBufferOffset:0];
            
            [renderEncoder endEncoding];
            [commandBuffer presentDrawable:this->_metalDrawable];
            this->_drawabletexture = this->_metalDrawable.texture;
            return commandBuffer;
        }
        
        bool init(int width,int height) {
            this->_frame.size.width  = this->_width  = width;
            this->_frame.size.height = this->_height = height;
            this->_metalLayer = [CAMetalLayer layer];
            this->_device = MTLCreateSystemDefaultDevice();
            this->_metalLayer.device = this->_device;
            this->_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            this->_metalLayer.colorspace = CGColorSpaceCreateDeviceRGB();
            this->_metalLayer.opaque = NO;
            this->_metalLayer.framebufferOnly = NO;
            this->_metalLayer.displaySyncEnabled = YES;
            this->_metalLayer.drawableSize = CGSizeMake(this->_width,this->_height);
            this->_commandQueue = [this->_device newCommandQueue];
            if(!this->_commandQueue) return false;
            NSError *error = nil;
          
            id<MTLLibrary> metallib = decodeMTLLibrary(this->_device,EmbeddedShader::$()->bytes,EmbeddedShader::$()->length);            
            if(metallib==nil) return false;
            this->_library.push_back(metallib);
            
            if(this->setupShader()) return false;	

            return this->setup();
        }
        
        void cleanup() { 
            this->_metalDrawable = nil; 
        }
        
        bool reloadShader(dispatch_data_t data, unsigned int index) {
            NSError *error = nil;
            this->_library[index] = [this->_device newLibraryWithData:data error:&error];
            if(error||!this->_library[index]) return true;
            if(this->updateShader(index)) return true;
            return false;
        }
        
        void resize(CGRect frame) {
            this->_frame = frame;
        }
        
        id<MTLCommandBuffer> prepareCommandBuffer() {
            if(!this->_metalDrawable) {
                this->_metalDrawable = [this->_metalLayer nextDrawable];
            }
            if(!this->_metalDrawable) {
                this->_renderPassDescriptor = nil;
            }
            else {
                if(this->_renderPassDescriptor == nil) this->_renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
            }
            if(this->_metalDrawable&&this->_renderPassDescriptor) {
                return this->setupCommandBuffer();
            }
            return nil;
        }
        
        void update(void (^onComplete)(id<MTLCommandBuffer>)) {
            if(this->_renderPipelineState[0]) {
                id<MTLCommandBuffer> commandBuffer = this->prepareCommandBuffer();
                if(commandBuffer) {
                    [commandBuffer addCompletedHandler:onComplete];
                    [commandBuffer commit];
                    [commandBuffer waitUntilCompleted];
                }
            }
        }
        
        CAMetalLayer *layer() {
            return this->_metalLayer;
        }	
};

class App {
    
    private:
        
        NSWindow  *_win;
        NSView *_view;
        MetalLayer *_layer;
        NSRect rect;
        dispatch_source_t timer;        
        unsigned int *texture = nullptr;    

    public:
        
        App() {
            
            int width  = 0;
            int height = 0;
                        
            this->texture = (unsigned int *)decodeJPEG(EmbeddedJPEG::$()->bytes,EmbeddedJPEG::$()->length,&width,&height);
            this->rect = CGRectMake(0,0,width,height);

            this->_win = [[NSWindow alloc] initWithContentRect:this->rect styleMask:1 backing:NSBackingStoreBuffered defer:NO];
            this->_view = [[NSView alloc] initWithFrame:this->rect];
                  
            this->_layer = new MetalLayer();
            
            if(this->_layer->init(this->rect.size.width,this->rect.size.height)) {
                this->_layer->resize(this->rect);
                [this->_view setWantsLayer:YES];
                this->_view.layer = this->_layer->layer();
                [[this->_win contentView] addSubview:this->_view];
            }
            
            CGRect screen = [[NSScreen mainScreen] frame];
            CGRect center = CGRectMake((screen.size.width-this->rect.size.width)*.5,(screen.size.height-this->rect.size.height)*.5,this->rect.size.width,this->rect.size.height);
            [this->_win setFrame:center display:YES];                    
            [this->_win makeKeyAndOrderFront:nil];            
            
            this->timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_queue_create("ENTER_FRAME",0));
            dispatch_source_set_timer(this->timer,dispatch_time(0,0),(1.0/30)*1000000000,0);
            dispatch_source_set_event_handler(this->timer,^{
                id<MTLTexture> texture = this->_layer->texture();
                [texture replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:this->texture bytesPerRow:width<<2];
                this->_layer->update(^(id<MTLCommandBuffer> commandBuffer){
                    this->_layer->cleanup();
                });
            });
            if(this->timer) dispatch_resume(this->timer);
        }
        
        ~App() {
            
            delete[] this->texture;    
            
            if(this->timer){
                dispatch_source_cancel(this->timer);
                this->timer = nullptr;
            }
                
            [this->_view removeFromSuperview];	
            [this->_win setReleasedWhenClosed:NO];
            [this->_win close];
            this->_win = nil;
        }
};

#pragma mark AppDelegate
@interface AppDelegate:NSObject <NSApplicationDelegate> {
    App *app;
}
@end
@implementation AppDelegate
-(void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    app = new App();
}
-(void)applicationWillTerminate:(NSNotification *)aNotification {
    delete app;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        id app = [NSApplication sharedApplication];
        id delegat = [AppDelegate alloc];
        [app setDelegate:delegat];
        [app run];
    }
}