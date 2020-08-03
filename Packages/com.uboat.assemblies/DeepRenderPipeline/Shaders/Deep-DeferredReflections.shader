// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Hidden/Deep-DeferredReflections" {
Properties {
	_LightAsQuad("", Float) = 0
    _SrcBlend ("", Float) = 1
    _DstBlend ("", Float) = 1
	_SrcABlend("", Float) = 1
	_DstABlend("", Float) = 1
	_CullMode("", Float) = 0
	_CompareFunc("", Float) = 0
}
SubShader {

// Calculates reflection contribution from a single probe (rendered as cubes) or default reflection (rendered as full screen quad)
Pass {
	Stencil
	{
		Ref [_CameraIndex]
		Comp Equal
	}

    ZWrite Off
	Cull [_CullMode]
	ZTest [_CompareFunc]
	Blend SrcAlpha OneMinusSrcAlpha
CGPROGRAM
#pragma target 3.0
#pragma vertex vert
#pragma fragment frag

#include "UnityCG.cginc"
#include "UnityDeferredLibrary.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardBRDF.cginc"
#include "UnityPBSLighting.cginc"

sampler2D _CameraGBufferTexture0;
sampler2D _CameraGBufferTexture1;
sampler2D _CameraGBufferTexture2;

UNITY_DECLARE_TEXCUBE(custom_SpecCube0);

CBUFFER_START(CustomReflectionProbes)
    float4 custom_SpecCube0_BoxMax;
    float4 custom_SpecCube0_BoxMin;
    float4 custom_SpecCube0_ProbePosition;
	float4 custom_SpecCube1_ProbePosition;
    half4  custom_SpecCube0_HDR;
CBUFFER_END

inline half3 UnityGI_IndirectSpecular2(UnityGIInput data, half occlusion, Unity_GlossyEnvironmentData glossIn)
{
    half3 specular;

    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
        // we will tweak reflUVW in glossIn directly (as we pass it to Unity_GlossyEnvironment twice for probe0 and probe1), so keep original to pass into BoxProjectedCubemapDirection
        half3 originalReflUVW = glossIn.reflUVW;
        glossIn.reflUVW = BoxProjectedCubemapDirection (originalReflUVW, data.worldPos, data.probePosition[0], data.boxMin[0], data.boxMax[0]);
    #endif

    #ifdef _GLOSSYREFLECTIONS_OFF
        specular = unity_IndirectSpecColor.rgb;
    #else
        half3 env0 = Unity_GlossyEnvironment (UNITY_PASS_TEXCUBE(custom_SpecCube0), data.probeHDR[0], glossIn);
        specular = env0;
    #endif

    return specular * occlusion;
}

half3 distanceFromAABB(half3 p, half3 aabbMin, half3 aabbMax)
{
    return max(max(p - aabbMax, aabbMin - p), half3(0.0, 0.0, 0.0));
}

unity_v2f_deferred vert (float4 vertex : POSITION, float3 normal : NORMAL)
{
    bool lightAsQuad = _LightAsQuad!=0.0;

    unity_v2f_deferred o;

    // scaling quad by two becuase built-in unity quad.fbx ranges from -0.5 to 0.5
    o.pos = lightAsQuad ? float4(2.0*vertex.xy, 0.5, 1.0) : UnityObjectToClipPos(vertex);
    o.uv = ComputeScreenPos(o.pos);

    // normal contains a ray pointing from the camera to one of near plane's
    // corners in camera space when we are drawing a full screen quad.
    // Otherwise, when rendering 3D shapes, use the ray calculated here.
    if (lightAsQuad){
    	float2 rayXY = mul(unity_CameraInvProjection, float4(o.pos.x, _ProjectionParams.x*o.pos.y, -1, 1)).xy;
        o.ray = float3(rayXY, 1.0);
    }
    else
    {
    	o.ray = UnityObjectToViewPos(vertex) * float3(-1,-1,1);
    }
    return o;
}

half4 frag (unity_v2f_deferred i) : SV_Target
{
    // Stripped from UnityDeferredCalculateLightParams, refactor into function ?
    i.ray = i.ray * (_ProjectionParams.z / i.ray.z);
    float2 uv = i.uv.xy / i.uv.w;

    // read depth and reconstruct world position
    float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
    depth = Linear01Depth (depth);
    float4 viewPos = float4(i.ray * depth,1);
    float3 worldPos = mul (unity_CameraToWorld, viewPos).xyz;

    half4 gbuffer0 = tex2D (_CameraGBufferTexture0, uv);
    half4 gbuffer1 = tex2D (_CameraGBufferTexture1, uv);
    half4 gbuffer2 = tex2D (_CameraGBufferTexture2, uv);
    UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);

    float3 eyeVec = normalize(worldPos - _WorldSpaceCameraPos);
    half oneMinusReflectivity = 1 - SpecularStrength(data.specularColor);

    half3 worldNormalRefl = reflect(eyeVec, data.normalWorld);

    // Unused member don't need to be initialized
    UnityGIInput d;
    d.worldPos = worldPos;
    d.worldViewDir = -eyeVec;
    d.probeHDR[0] = custom_SpecCube0_HDR;
    d.boxMin[0].w = 1; // 1 in .w allow to disable blending in UnityGI_IndirectSpecular call since it doesn't work in Deferred

    float blendDistance = custom_SpecCube1_ProbePosition.w; // will be set to blend distance for this probe
    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
    d.probePosition[0]  = custom_SpecCube0_ProbePosition;
    d.boxMin[0].xyz     = custom_SpecCube0_BoxMin - float4(blendDistance,blendDistance,blendDistance,0);
    d.boxMax[0].xyz     = custom_SpecCube0_BoxMax + float4(blendDistance,blendDistance,blendDistance,0);
    #endif

    Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(data.smoothness, d.worldViewDir, data.normalWorld, data.specularColor);

    half3 env0 = UnityGI_IndirectSpecular2(d, data.occlusion, g);

    UnityLight light;
    light.color = half3(0, 0, 0);
    light.dir = half3(0, 1, 0);

    UnityIndirect ind;
    ind.diffuse = 0;
    ind.specular = env0;

    half3 rgb = UNITY_BRDF_PBS (0, data.specularColor, oneMinusReflectivity, data.smoothness, data.normalWorld, -eyeVec, light, ind).rgb;

    // Calculate falloff value, so reflections on the edges of the probe would gradually blend to previous reflection.
    // Also this ensures that pixels not located in the reflection probe AABB won't
    // accidentally pick up reflections from this probe.
    half3 distance = distanceFromAABB(worldPos, custom_SpecCube0_BoxMin.xyz, custom_SpecCube0_BoxMax.xyz);
    half falloff = saturate(1.0 - length(distance)/blendDistance);

    return half4(rgb, falloff);
}

ENDCG
}

// Adds reflection buffer to the lighting buffer
Pass
{
    ZWrite Off
    ZTest Always
    Blend One One

    CGPROGRAM
        #pragma target 3.0
        #pragma vertex vert
        #pragma fragment frag
        #define UNITY_HDR_ON 1

        #include "UnityCG.cginc"

        sampler2D _CameraReflectionsTexture;

        struct v2f {
            float2 uv : TEXCOORD0;
            float4 pos : SV_POSITION;
        };

        v2f vert (float4 vertex : POSITION)
        {
            v2f o;
            o.pos = UnityObjectToClipPos(vertex);
            o.uv = ComputeScreenPos (o.pos).xy;
            return o;
        }

        half4 frag (v2f i) : SV_Target
        {
            half4 c = tex2D (_CameraReflectionsTexture, i.uv);
            return float4(c.rgb, 0.0f);

        }
    ENDCG
}

}
Fallback Off
}
