//
//  Shaders.metal
//  NeonInvaders Shared
//

#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"

using namespace metal;

typedef struct {
    float4 position [[position]];
    float4 color;
} VertexOut;

vertex VertexOut spriteVertex(
    uint vertexID [[vertex_id]],
    constant SpriteVertex* vertices [[buffer(BufferIndexVertices)]],
    constant GameUniforms& uniforms [[buffer(BufferIndexUniforms)]])
{
    VertexOut out;
    SpriteVertex v = vertices[vertexID];
    float2 ndc;
    ndc.x = (v.position.x / uniforms.resolution.x) * 2.0 - 1.0;
    ndc.y = 1.0 - (v.position.y / uniforms.resolution.y) * 2.0;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 spriteFragment(VertexOut in [[stage_in]])
{
    return in.color;
}
