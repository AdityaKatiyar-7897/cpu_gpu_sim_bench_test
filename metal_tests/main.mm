#include <Metal/Metal.h>
#include <Foundation/Foundation.h>
#include <stdio.h>

static const char *metal_code = R"(
#include <metal_stdlib>
using namespace metal;

/*
  GPU KERNEL

  This function runs on the GPU.

  Each GPU thread gets its own id:

      thread 0 -> data[0]
      thread 1 -> data[1]
      thread 2 -> data[2]
*/
kernel void add_ten(
    device int *data [[buffer(0)]],
    uint id [[thread_position_in_grid]])
{
    data[id] += 10;
}
)";

int main(void)
{
    @autoreleasepool
    {
        int data[5] = {0, 1, 2, 3, 4};

        printf("before: ");
        for (int i = 0; i < 5; i++)
            printf("%d ", data[i]);
        printf("\n");

        /*
          METAL DEVICE

          This is your Apple GPU.
        */
        id<MTLDevice> device =
            MTLCreateSystemDefaultDevice();

        /*
          COMPILE GPU CODE

          We compile the Metal kernel from the string above.
        */
        NSError *error = nil;

        id<MTLLibrary> library =
            [device newLibraryWithSource:
                        [NSString stringWithUTF8String:metal_code]
                                    options:nil
                                      error:&error];

        if (!library)
        {
            printf("Metal compile error: %s\n",
                   [[error localizedDescription] UTF8String]);
            return 1;
        }

        /*
          FIND THE KERNEL FUNCTION
        */
        id<MTLFunction> function =
            [library newFunctionWithName:@"add_ten"];

        /*
          MAKE PIPELINE

          Pipeline = GPU knows how to run this kernel.
        */
        id<MTLComputePipelineState> pipeline =
            [device newComputePipelineStateWithFunction:function
                                                   error:&error];

        /*
          GPU BUFFER

          Copy CPU array into memory that GPU can access.
        */
        id<MTLBuffer> buffer =
            [device newBufferWithBytes:data
                                 length:sizeof(data)
                                options:MTLResourceStorageModeShared];

        /*
          COMMAND QUEUE

          CPU puts GPU jobs into this queue.
        */
        id<MTLCommandQueue> queue =
            [device newCommandQueue];

        /*
          COMMAND BUFFER

          One packet of GPU work.
        */
        id<MTLCommandBuffer> command_buffer =
            [queue commandBuffer];

        /*
          ENCODER

          Describes what compute work the GPU should do.
        */
        id<MTLComputeCommandEncoder> encoder =
            [command_buffer computeCommandEncoder];

        [encoder setComputePipelineState:pipeline];

        /*
          buffer(0) in Metal code receives this buffer.
        */
        [encoder setBuffer:buffer
                    offset:0
                   atIndex:0];

        /*
          Run 5 GPU threads.

          Thread 0 modifies data[0]
          Thread 1 modifies data[1]
          ...
          Thread 4 modifies data[4]
        */
        MTLSize grid =
            MTLSizeMake(5, 1, 1);

        MTLSize group =
            MTLSizeMake(5, 1, 1);

        [encoder dispatchThreads:grid
            threadsPerThreadgroup:group];

        [encoder endEncoding];

        /*
          SEND WORK TO GPU
        */
        [command_buffer commit];

        /*
          Wait so CPU can read result.
        */
        [command_buffer waitUntilCompleted];

        /*
          READ BACK RESULT
        */
        int *result =
            (int *)[buffer contents];

        printf("after:  ");
        for (int i = 0; i < 5; i++)
            printf("%d ", result[i]);
        printf("\n");
    }

    return 0;
}
