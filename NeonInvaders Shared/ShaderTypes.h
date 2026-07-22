//
//  ShaderTypes.h
//  NeonInvaders Shared
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

typedef NS_ENUM(EnumBackingType, BufferIndex) {
    BufferIndexVertices = 0,
    BufferIndexUniforms = 1,
};

typedef struct {
    vector_float2 position;
    vector_float4 color;
} SpriteVertex;

typedef struct {
    vector_float2 position;
    vector_float2 uv;
    vector_float4 color;
} TexVertex;

typedef struct {
    vector_float2 resolution;
    float time;
    float padding;
} GameUniforms;

#endif /* ShaderTypes_h */
