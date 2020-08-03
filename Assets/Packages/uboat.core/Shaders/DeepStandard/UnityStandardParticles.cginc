// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

#ifndef UNITY_STANDARD_CORE_INCLUDED
#define UNITY_STANDARD_CORE_INCLUDED

#include "UnityCG.cginc"
#include "UnityShaderVariables.cginc"
#include "UnityStandardBRDF.cginc"
#include "UnityStandardConfig.cginc"
#include "UnityStandardInput.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"

#include "AutoLight.cginc"

// EDITS START
#define COMPENSATE_EARTH_CURVATURE_PER_VERTEX 1
#include "PlayWay Water/Shaders/Includes/EarthCurvature.cginc"
#include "DeepStandardLib.cginc"
// EDITS END

half2 _UnderwaterMaskFactors;
half3 _SubsurfaceScatteringColor;

#if _REQUIRE_UV2
#define _FLIPBOOK_BLENDING 1
#endif

#if EFFECT_BUMP
#define _DISTORTION_ON 1
#endif

// Vertex shader input
struct appdata_particles
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float4 color : COLOR;
    #if defined(_FLIPBOOK_BLENDING)
    float4 texcoords : TEXCOORD0;
    float texcoordBlend : TEXCOORD1;
    #else
    float2 texcoords : TEXCOORD0;
    #endif
    #if defined(_NORMALMAP)
    float4 tangent : TANGENT;
    #endif
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

sampler2D _CameraDepthTexture;

float4 _SoftParticleFadeParams;
float4 _CameraFadeParams;
half _LightDesaturation;
half _LightingSoftness;

#define SOFT_PARTICLE_NEAR_FADE _SoftParticleFadeParams.x
#define SOFT_PARTICLE_INV_FADE_DISTANCE _SoftParticleFadeParams.y

#define CAMERA_NEAR_FADE _CameraFadeParams.x
#define CAMERA_INV_FADE_DISTANCE _CameraFadeParams.y

#if _DISTORTION_ON
sampler2D _GrabTexture;
half _DistortionStrengthScaled;
half _DistortionBlend;
#endif

#if defined (_COLORADDSUBDIFF_ON)
half4 _ColorAddSubDiff;
#endif

#if defined(_COLORCOLOR_ON)
half3 RGBtoHSV(half3 arg1)
{
    half4 K = half4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    half4 P = lerp(half4(arg1.bg, K.wz), half4(arg1.gb, K.xy), step(arg1.b, arg1.g));
    half4 Q = lerp(half4(P.xyw, arg1.r), half4(arg1.r, P.yzx), step(P.x, arg1.r));
    half D = Q.x - min(Q.w, Q.y);
    half E = 1e-10;
    return half3(abs(Q.z + (Q.w - Q.y) / (6.0 * D + E)), D / (Q.x + E), Q.x);
}

half3 HSVtoRGB(half3 arg1)
{
    half4 K = half4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    half3 P = abs(frac(arg1.xxx + K.xyz) * 6.0 - K.www);
    return arg1.z * lerp(K.xxx, saturate(P - K.xxx), arg1.y);
}
#endif

// Flipbook vertex function
#if defined(_FLIPBOOK_BLENDING)
#define vertTexcoord(v, o) \
    o.texcoord = v.texcoords.xy; \
    o.texcoord2AndBlend.xy = v.texcoords.zw; \
    o.texcoord2AndBlend.z = v.texcoordBlend;
#else
#define vertTexcoord(v, o) \
    o.texcoord = TRANSFORM_TEX(v.texcoords.xy, _MainTex);
#endif

// Fading vertex function
#if /*defined(SOFTPARTICLES_ON) || */defined(_FADING_ON)
#define vertFading(o) \
    o.projectedPosition = ComputeScreenPos (clipPosition); \
    COMPUTE_EYEDEPTH(o.projectedPosition.z);
#else
#define vertFading(o)
#endif

// Distortion vertex function
//#if _DISTORTION_ON || _MASK_UNDERWATER
#define vertDistortion(o) \
    o.grabPassPosition = ComputeGrabScreenPos (clipPosition);
//#else
//#define vertDistortion(o)
//#endif

// Color blending fragment function
#if defined(_COLOROVERLAY_ON)
#define fragColorMode(i) \
    albedo.rgb = lerp(1 - 2 * (1 - albedo.rgb) * (1 - i.color.rgb), 2 * albedo.rgb * i.color.rgb, step(albedo.rgb, 0.5)); \
    albedo.a *= i.color.a;
#elif defined(_COLORCOLOR_ON)
#define fragColorMode(i) \
    half3 aHSL = RGBtoHSV(albedo.rgb); \
    half3 bHSL = RGBtoHSV(i.color.rgb); \
    half3 rHSL = fixed3(bHSL.x, bHSL.y, aHSL.z); \
    albedo = fixed4(HSVtoRGB(rHSL), albedo.a * i.color.a);
#elif defined(_COLORADDSUBDIFF_ON)
#define fragColorMode(i) \
    albedo.rgb = albedo.rgb + i.color.rgb * _ColorAddSubDiff.x; \
    albedo.rgb = lerp(albedo.rgb, abs(albedo.rgb), _ColorAddSubDiff.y); \
    albedo.a *= i.color.a;
#else
#define fragColorMode(i) \
    albedo *= i.color;
#endif

// Pre-multiplied alpha helper
#if defined(_ALPHAPREMULTIPLY_ON)
#define ALBEDO_MUL albedo
#else
#define ALBEDO_MUL albedo.a
#endif

// Soft particles fragment function
#if /*defined(SOFTPARTICLES_ON) && */defined(_FADING_ON)
#define fragSoftParticles(i) \
    if (SOFT_PARTICLE_NEAR_FADE > 0.0 || SOFT_PARTICLE_INV_FADE_DISTANCE > 0.0) \
    { \
        float sceneZ = LinearEyeDepth (SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.projectedPosition))); \
        float fade = saturate (SOFT_PARTICLE_INV_FADE_DISTANCE * ((sceneZ - SOFT_PARTICLE_NEAR_FADE) - i.projectedPosition.z)); \
        ALBEDO_MUL *= fade; \
    }
#else
#define fragSoftParticles(i)
#endif

// Camera fading fragment function
#if defined(_FADING_ON)
#define fragCameraFading(i) \
    float cameraFade = saturate((i.projectedPosition.z - CAMERA_NEAR_FADE) * CAMERA_INV_FADE_DISTANCE); \
    ALBEDO_MUL *= cameraFade;
#else
#define fragCameraFading(i)
#endif

#if defined(_ANGULAR_FADING_ON)
#define fragCameraAngularFading(normalWorld, cameraLookVector) \
    float cameraFade = abs(dot(normalWorld, cameraLookVector)); \
    s.alpha *= cameraFade;
#else
#define fragCameraAngularFading(normalWorld, cameraLookVector)
#endif

#if _DISTORTION_ON
#define fragDistortion(i) \
    float4 grabPosUV = UNITY_PROJ_COORD(i.grabPassPosition); \
    grabPosUV.xy += normal.xy * _DistortionStrengthScaled * albedo.a; \
    half3 grabPass = tex2Dproj(_GrabTexture, grabPosUV).rgb; \
    albedo.rgb = lerp(grabPass, albedo.rgb, saturate(albedo.a - _DistortionBlend));
#else
#define fragDistortion(i)
#endif

//-------------------------------------------------------------------------------------
// counterpart for NormalizePerPixelNormal
// skips normalization per-vertex and expects normalization to happen per-pixel
half3 NormalizePerVertexNormal (float3 n) // takes float to avoid overflow
{
    #if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
        return normalize(n);
    #else
        return n; // will normalize per-pixel instead
    #endif
}

float3 NormalizePerPixelNormal (float3 n)
{
    #if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
        return n;
    #else
        return normalize(n);
    #endif
}

//-------------------------------------------------------------------------------------
UnityLight MainLight ()
{
    UnityLight l;

    l.color = _LightColor0.rgb;
    l.dir = _WorldSpaceLightPos0.xyz;
    return l;
}

UnityLight AdditiveLight (half3 lightDir, half atten)
{
    UnityLight l;

    l.color = _LightColor0.rgb;
    l.dir = lightDir;
    #ifndef USING_DIRECTIONAL_LIGHT
        l.dir = NormalizePerPixelNormal(l.dir);
    #endif

    // shadow the light
    l.color *= atten;
    return l;
}

UnityLight DummyLight ()
{
    UnityLight l;
    l.color = 0;
    l.dir = half3 (0,1,0);
    return l;
}

UnityIndirect ZeroIndirect ()
{
    UnityIndirect ind;
    ind.diffuse = 0;
    ind.specular = 0;
    return ind;
}

//-------------------------------------------------------------------------------------
// Common fragment setup

// deprecated
half3 WorldNormal(half4 tan2world[3])
{
    return normalize(tan2world[2].xyz);
}

// deprecated
#ifdef _TANGENT_TO_WORLD
    half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
    {
        half3 t = tan2world[0].xyz;
        half3 b = tan2world[1].xyz;
        half3 n = tan2world[2].xyz;

    #if UNITY_TANGENT_ORTHONORMALIZE
        n = NormalizePerPixelNormal(n);

        // ortho-normalize Tangent
        t = normalize (t - n * dot(t, n));

        // recalculate Binormal
        half3 newB = cross(n, t);
        b = newB * sign (dot (newB, b));
    #endif

        return half3x3(t, b, n);
    }
#else
    half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
    {
        return half3x3(0,0,0,0,0,0,0,0,0);
    }
#endif

float3 PerPixelWorldNormal(float4 i_tex, float4 tangentToWorld[3])
{
#ifdef _NORMALMAP
    half3 tangent = tangentToWorld[0].xyz;
    half3 binormal = tangentToWorld[1].xyz;
    half3 normal = tangentToWorld[2].xyz;

    #if UNITY_TANGENT_ORTHONORMALIZE
        normal = NormalizePerPixelNormal(normal);

        // ortho-normalize Tangent
        tangent = normalize (tangent - normal * dot(tangent, normal));

        // recalculate Binormal
        half3 newB = cross(normal, tangent);
        binormal = newB * sign (dot (newB, binormal));
    #endif

    half3 normalTangent = NormalInTangentSpace(i_tex);
    float3 normalWorld = NormalizePerPixelNormal(tangent * normalTangent.x + binormal * normalTangent.y + normal * normalTangent.z); // @TODO: see if we can squeeze this normalize on SM2.0 as well
#else
    float3 normalWorld = normalize(tangentToWorld[2].xyz);
#endif
    return normalWorld;
}

#ifdef _PARALLAXMAP
    #define IN_VIEWDIR4PARALLAX(i) NormalizePerPixelNormal(half3(i.tangentToWorldAndPackedData[0].w,i.tangentToWorldAndPackedData[1].w,i.tangentToWorldAndPackedData[2].w))
    #define IN_VIEWDIR4PARALLAX_FWDADD(i) NormalizePerPixelNormal(i.viewDirForParallax.xyz)
#else
    #define IN_VIEWDIR4PARALLAX(i) half3(0,0,0)
    #define IN_VIEWDIR4PARALLAX_FWDADD(i) half3(0,0,0)
#endif

#define UNITY_REQUIRE_FRAG_WORLDPOS 1

#if UNITY_REQUIRE_FRAG_WORLDPOS
    #if UNITY_PACK_WORLDPOS_WITH_TANGENT
        #define IN_WORLDPOS(i) half3(i.tangentToWorldAndPackedData[0].w,i.tangentToWorldAndPackedData[1].w,i.tangentToWorldAndPackedData[2].w)
    #else
        #define IN_WORLDPOS(i) i.posWorld
    #endif
    #define IN_WORLDPOS_FWDADD(i) i.posWorld
#else
    #define IN_WORLDPOS(i) half3(0,0,0)
    #define IN_WORLDPOS_FWDADD(i) half3(0,0,0)
#endif

#define IN_LIGHTDIR_FWDADD(i) half3(i.tangentToWorldAndLightDir[0].w, i.tangentToWorldAndLightDir[1].w, i.tangentToWorldAndLightDir[2].w)

#define FRAGMENT_SETUP(x) FragmentCommonData x = \
    FragmentSetup(i.texcoord, i.eyeVec, IN_VIEWDIR4PARALLAX(i), i.tangentToWorldAndPackedData, IN_WORLDPOS(i));

struct FragmentCommonData
{
    half3 diffColor, specColor;
    // Note: smoothness & oneMinusReflectivity for optimization purposes, mostly for DX9 SM2.0 level.
    // Most of the math is being done on these (1-x) values, and that saves a few precious ALU slots.
    half oneMinusReflectivity, smoothness;
    float3 normalWorld;
    float3 eyeVec;
    half alpha;
    float3 posWorld;

#if UNITY_STANDARD_SIMPLE
    half3 reflUVW;
#endif

#if UNITY_STANDARD_SIMPLE
    half3 tangentSpaceNormal;
#endif
};

#ifndef UNITY_SETUP_BRDF_INPUT
    #define UNITY_SETUP_BRDF_INPUT SpecularSetup
#endif

inline FragmentCommonData SpecularSetup (float4 i_tex)
{
    half4 specGloss = SpecularGloss(i_tex.xy);
    half3 specColor = specGloss.rgb;
    half smoothness = specGloss.a;

    half oneMinusReflectivity;
    half3 diffColor = EnergyConservationBetweenDiffuseAndSpecular (Albedo(i_tex), specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

inline FragmentCommonData RoughnessSetup(float4 i_tex)
{
    half2 metallicGloss = MetallicRough(i_tex.xy);
    half metallic = metallicGloss.x;
    half smoothness = metallicGloss.y; // this is 1 minus the square root of real roughness m.

    half oneMinusReflectivity;
    half3 specColor;
    half3 diffColor = DiffuseAndSpecularFromMetallic(Albedo(i_tex), metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

inline FragmentCommonData MetallicSetup (float4 i_tex)
{
    half2 metallicGloss = MetallicGloss(i_tex.xy);
    half metallic = metallicGloss.x;
    half smoothness = metallicGloss.y; // this is 1 minus the square root of real roughness m.

    half oneMinusReflectivity;
    half3 specColor;
    half3 diffColor = DiffuseAndSpecularFromMetallic (Albedo(i_tex), metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

// parallax transformed texcoord is used to sample occlusion
inline FragmentCommonData FragmentSetup (inout float4 i_tex, float3 i_eyeVec, half3 i_viewDirForParallax, float4 tangentToWorld[3], float3 i_posWorld)
{
    half alpha = Alpha(i_tex.xy);
    #if defined(_ALPHATEST_ON)
        clip (alpha - _Cutoff);
    #endif

    FragmentCommonData o = UNITY_SETUP_BRDF_INPUT (i_tex);
    o.normalWorld = PerPixelWorldNormal(i_tex, tangentToWorld);
    o.eyeVec = NormalizePerPixelNormal(i_eyeVec);
    o.posWorld = i_posWorld;

    // NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
    o.diffColor = PreMultiplyAlpha (o.diffColor, alpha, o.oneMinusReflectivity, /*out*/ o.alpha);
    return o;
}

inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light, bool reflections)
{
    UnityGIInput d;
    d.light = light;
    d.worldPos = s.posWorld;
    d.worldViewDir = -s.eyeVec;
    d.atten = atten;
    #if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
        d.ambient = 0;
        d.lightmapUV = i_ambientOrLightmapUV;
    #else
        d.ambient = i_ambientOrLightmapUV.rgb;
        d.lightmapUV = 0;
    #endif

    d.probeHDR[0] = unity_SpecCube0_HDR;
    d.probeHDR[1] = unity_SpecCube1_HDR;
    #if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
      d.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
    #endif
    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
      d.boxMax[0] = unity_SpecCube0_BoxMax;
      d.probePosition[0] = unity_SpecCube0_ProbePosition;
      d.boxMax[1] = unity_SpecCube1_BoxMax;
      d.boxMin[1] = unity_SpecCube1_BoxMin;
      d.probePosition[1] = unity_SpecCube1_ProbePosition;
    #endif

    if(reflections)
    {
        Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.smoothness, -s.eyeVec, s.normalWorld, s.specColor);
        // Replace the reflUVW if it has been compute in Vertex shader. Note: the compiler will optimize the calcul in UnityGlossyEnvironmentSetup itself
        #if UNITY_STANDARD_SIMPLE
            g.reflUVW = s.reflUVW;
        #endif

        return UnityGlobalIllumination (d, occlusion, s.normalWorld, g);
    }
    else
    {
        return UnityGlobalIllumination (d, occlusion, s.normalWorld);
    }
}

inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light)
{
    return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, true);
}


//-------------------------------------------------------------------------------------
half4 OutputForward (half4 output, half alphaFromSurface)
{
    #if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
        output.a = alphaFromSurface;
    #else
        UNITY_OPAQUE_ALPHA(output.a);
    #endif
    return output;
}

inline half4 VertexGIForward(appdata_particles v, float3 posWorld, half3 normalWorld)
{
    half4 ambientOrLightmapUV = 0;
    // Static lightmaps
    #ifdef LIGHTMAP_ON
        ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
        ambientOrLightmapUV.zw = 0;
    // Sample light probe for Dynamic objects only (no static or dynamic lightmaps)
    #elif UNITY_SHOULD_SAMPLE_SH
        #ifdef VERTEXLIGHT_ON
            // Approximated illumination from non-important point lights
            ambientOrLightmapUV.rgb = Shade4PointLights (
                unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
                unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
                unity_4LightAtten0, posWorld, normalWorld);
        #endif

        ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, ambientOrLightmapUV.rgb);
    #endif

    #ifdef DYNAMICLIGHTMAP_ON
        ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif

    return ambientOrLightmapUV;
}

// ------------------------------------------------------------------
//  Base forward pass (directional light, emission, lightmaps, ...)

struct VertexOutputForwardBase
{
	UNITY_POSITION(pos);
	float2 texcoord : TEXCOORD0;
    float3 eyeVec                         : TEXCOORD1;
    float4 tangentToWorldAndPackedData[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:viewDirForParallax or worldPos]
    half4 ambientOrLightmapUV             : TEXCOORD5;    // SH or Lightmap UV

	float4 color : TEXCOORD6;
    #if defined(_FLIPBOOK_BLENDING)
    float3 texcoord2AndBlend : TEXCOORD7;
    #endif
    #if /*defined(SOFTPARTICLES_ON) || */defined(_FADING_ON)
    float4 projectedPosition : TEXCOORD8;
    #endif
    //#if _DISTORTION_ON || _MASK_UNDERWATER
    float4 grabPassPosition : TEXCOORD10;
    //#endif

	UNITY_FOG_COORDS(11)

        // next ones would not fit into SM2.0 limits, but they are always for SM3.0+
    #if UNITY_REQUIRE_FRAG_WORLDPOS && !UNITY_PACK_WORLDPOS_WITH_TANGENT
        float3 posWorld                 : TEXCOORD9;
    #endif

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

VertexOutputForwardBase vertForwardBase (appdata_particles v)
{
    UNITY_SETUP_INSTANCE_ID(v);
    VertexOutputForwardBase o;
    UNITY_INITIALIZE_OUTPUT(VertexOutputForwardBase, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);

	#if defined(USE_CUSTOM_AMBIENT)			// apply earth curvature effect only to exterior meshes
		posWorld = CompensateForEarthCurvature(posWorld);
	#endif

    #if UNITY_REQUIRE_FRAG_WORLDPOS
        #if UNITY_PACK_WORLDPOS_WITH_TANGENT
            o.tangentToWorldAndPackedData[0].w = posWorld.x;
            o.tangentToWorldAndPackedData[1].w = posWorld.y;
            o.tangentToWorldAndPackedData[2].w = posWorld.z;
        #else
            o.posWorld = posWorld.xyz;
        #endif
    #endif
	float4 clipPosition = mul(UNITY_MATRIX_VP, posWorld);
	o.pos = clipPosition;
	o.color = v.color;

	vertTexcoord(v, o);
	vertFading(o);
	vertDistortion(o);

    o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
    float3 normalWorld = UnityObjectToWorldNormal(v.normal);
    #ifdef _TANGENT_TO_WORLD
        float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

        float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
        o.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
        o.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
        o.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
    #else
        o.tangentToWorldAndPackedData[0].xyz = 0;
        o.tangentToWorldAndPackedData[1].xyz = 0;
        o.tangentToWorldAndPackedData[2].xyz = normalWorld;
    #endif

    //We need this for shadow receving
    UNITY_TRANSFER_LIGHTING(o, v.uv1);

    o.ambientOrLightmapUV = VertexGIForward(v, posWorld, normalWorld);

    #ifdef _PARALLAXMAP
        TANGENT_SPACE_ROTATION;
        half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
        o.tangentToWorldAndPackedData[0].w = viewDirForParallax.x;
        o.tangentToWorldAndPackedData[1].w = viewDirForParallax.y;
        o.tangentToWorldAndPackedData[2].w = viewDirForParallax.z;
    #endif

    UNITY_TRANSFER_FOG(o,o.pos);
    return o;
}

// SRP START ----
#define MAX_VISIBLE_LIGHTS 32

half4 unity_LightIndicesOffsetAndCount;
half4 unity_4LightIndices0;
half4 unity_4LightIndices1;
int _DirectionalLightsCount;

CBUFFER_START(_PerCamera)
	half4 _LightCount;
	int _LightShadowIndices[MAX_VISIBLE_LIGHTS];
	float4 _LightPosition[MAX_VISIBLE_LIGHTS];
	half4 _LightListColor[MAX_VISIBLE_LIGHTS];
	half4 _LightDistanceAttenuation[MAX_VISIBLE_LIGHTS];
	half4 _LightSpotDir[MAX_VISIBLE_LIGHTS];
CBUFFER_END

struct DeepLight
{
	half4 distanceAttenuation;
	half3 color;
	float3 dir;
};

StructuredBuffer<int> _LightIndexBuffer;

#include "LightingTemplate.hlsl"

DeepLight GetLight(int index)
{
	DeepLight light;

	light.distanceAttenuation = _LightDistanceAttenuation[index];
	light.color = _LightListColor[index];
	light.dir = _LightPosition[index];

	return light;
}

half DistanceAttenuation(half distanceSqr, half3 distanceAttenuation)
{
	// We use a shared distance attenuation for additional directional and puctual lights
	// for directional lights attenuation will be 1
	half quadFalloff = distanceAttenuation.x;
	half denom = distanceSqr * quadFalloff + 1.0h;
	half lightAtten = 1.0h / denom;

	// We need to smoothly fade attenuation to light range. We start fading linearly at 80% of light range
	// Therefore:
	// fadeDistance = (0.8 * 0.8 * lightRangeSq)
	// smoothFactor = (lightRangeSqr - distanceSqr) / (lightRangeSqr - fadeDistance)
	// We can rewrite that to fit a MAD by doing
	// distanceSqr * (1.0 / (fadeDistanceSqr - lightRangeSqr)) + (-lightRangeSqr / (fadeDistanceSqr - lightRangeSqr)
	// distanceSqr *        distanceAttenuation.y            +             distanceAttenuation.z
	half smoothFactor = saturate(distanceSqr * distanceAttenuation.y + distanceAttenuation.z);
	return lightAtten * smoothFactor;
}

UnityLight ToUnityLight(DeepLight light, half3 normalWorld)
{
	UnityLight unityLight;
	unityLight.color = light.color;
	unityLight.dir = light.dir;
	unityLight.ndotl = saturate(dot(normalWorld, light.dir));
	return unityLight;
}

half3 EvaluatePunctualLight(FragmentCommonData s, DeepLight light, int lightIndex, ShadowContext shadowContext, half3 subsurfaceScatteringColor)
{
	UnityIndirect noIndirect = ZeroIndirect();
	half atten = 1.0;

	half3 tolight = light.dir.xyz - s.posWorld;
	half3 lightDir = normalize(tolight);
	atten = DistanceAttenuation(dot(tolight, tolight), light.distanceAttenuation.xyz);

	half4 spotDir = _LightSpotDir[lightIndex];

	if (spotDir.w != 0.0)
	{
		half SdotL = dot(spotDir.xyz, lightDir);
		half atten1 = saturate(SdotL * spotDir.w + light.distanceAttenuation.w);
		atten *= atten1 * atten1;
	}

#if defined(_PARTICLE_SHADOWS)
	int shadowIndex = _LightShadowIndices[lightIndex];

	UNITY_BRANCH if (shadowIndex >= 0)
	{
		atten *= GetPunctualShadowAttenuation(shadowContext, s.posWorld, s.normalWorld, shadowIndex, lightDir, length(tolight));
	}
#endif

	lightDir = lerp(lightDir, s.normalWorld, _LightingSoftness);
	light.dir = lightDir;

	light.color *= atten;

	return UNITY_BRDF_PBS(s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, ToUnityLight(light, s.normalWorld), noIndirect, subsurfaceScatteringColor).rgb;
}

half3 EvaluateDirectionalLight(FragmentCommonData s, DeepLight light, int lightIndex, ShadowContext shadowContext, half3 subsurfaceScatteringColor)
{
	UnityIndirect noIndirect = ZeroIndirect();

#if defined(_PARTICLE_SHADOWS)
	int shadowIndex = _LightShadowIndices[lightIndex];
	half atten = 1.0;

	UNITY_BRANCH if (shadowIndex >= 0)
	{
		atten = GetDirectionalShadowAttenuation(shadowContext, s.posWorld, s.normalWorld, shadowIndex, light.dir.xyz, length(light.dir.xyz));
	}

	light.color *= atten;
#endif

	return UNITY_BRDF_PBS(s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, ToUnityLight(light, s.normalWorld), noIndirect, subsurfaceScatteringColor).rgb;
}

float3 PerPixelWorldNormal(half3 normalTangent, float4 tangentToWorld[3])
{
#ifdef _NORMALMAP
    half3 tangent = tangentToWorld[0].xyz;
    half3 binormal = tangentToWorld[1].xyz;
    half3 normal = tangentToWorld[2].xyz;

    #if UNITY_TANGENT_ORTHONORMALIZE
        normal = NormalizePerPixelNormal(normal);

        // ortho-normalize Tangent
        tangent = normalize (tangent - normal * dot(tangent, normal));

        // recalculate Binormal
        half3 newB = cross(normal, tangent);
        binormal = newB * sign (dot (newB, binormal));
    #endif

    float3 normalWorld = NormalizePerPixelNormal(tangent * normalTangent.x + binormal * normalTangent.y + normal * normalTangent.z); // @TODO: see if we can squeeze this normalize on SM2.0 as well
#else
    float3 normalWorld = normalize(tangentToWorld[2].xyz);
#endif
    return normalWorld;
}

half GetPixelLightCount()
{
	//return min(_LightCount.x - unity_LightIndicesOffsetAndCount.x, unity_LightIndicesOffsetAndCount.y);
	return unity_LightIndicesOffsetAndCount.y;
}

fixed4 readTexture(sampler2D tex, VertexOutputForwardBase IN)
{
    fixed4 color = tex2D (tex, IN.texcoord);
    #ifdef _FLIPBOOK_BLENDING
    fixed4 color2 = tex2D(tex, IN.texcoord2AndBlend.xy);
    color = lerp(color, color2, IN.texcoord2AndBlend.z);
    #endif
    return color;
}

void surf (VertexOutputForwardBase IN, inout SurfaceOutputStandard o)
{
    half4 albedo = readTexture (_MainTex, IN);
    albedo *= _Color;

    fragColorMode(IN);
    fragSoftParticles(IN);
    fragCameraFading(IN);

    #if defined(_METALLICGLOSSMAP)
    fixed2 metallicGloss = readTexture (_MetallicGlossMap, IN).ra * fixed2(1.0, _Glossiness);
    #else
    fixed2 metallicGloss = fixed2(_Metallic, _Glossiness);
    #endif

    #if defined(_NORMALMAP)
    float3 normal = normalize (UnpackScaleNormal (readTexture (_BumpMap, IN), _BumpScale));
    #else
    float3 normal = float3(0,0,1);
    #endif

    #if defined(_EMISSION)
    half3 emission = readTexture (_EmissionMap, IN).rgb;
    #else
    half3 emission = 0;
    #endif

    fragDistortion(IN);

    o.Albedo = albedo.rgb;
    o.Normal = normal;
    o.Emission = emission * _EmissionColor;
    o.Metallic = metallicGloss.r;
    o.Smoothness = metallicGloss.g;
	o.Occlusion = 1;

    #if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON) || defined(_ALPHAOVERLAY_ON)
    o.Alpha = albedo.a;
    #else
    o.Alpha = 1;
    #endif

    #if defined(_ALPHAMODULATE_ON)
    o.Albedo = lerp(1.0, albedo.rgb, albedo.a);
    #endif

    #if defined(_ALPHATEST_ON)
    clip (albedo.a - _Cutoff + 0.0001);
    #endif
}

void fragForwardBaseSRP (out half4 outColor : SV_Target0, out half4 outFog : SV_Target1, VertexOutputForwardBase i)
{
#if _MASK_UNDERWATER
	half underwaterMask = tex2Dproj(_UnderwaterMask, i.grabPassPosition);
	clip(underwaterMask * _UnderwaterMaskFactors.x + _UnderwaterMaskFactors.y);
#endif

    //UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

    //FRAGMENT_SETUP(s)
	FragmentCommonData s;
	SurfaceOutputStandard sos;
	surf(i, sos);
	s.smoothness = sos.Smoothness;
	s.normalWorld = PerPixelWorldNormal(sos.Normal, i.tangentToWorldAndPackedData);
	s.diffColor = DiffuseAndSpecularFromMetallic(sos.Albedo, sos.Metallic, /*out*/ s.specColor, /*out*/ s.oneMinusReflectivity);
	s.eyeVec = NormalizePerPixelNormal(i.eyeVec);
	s.posWorld = half3(i.tangentToWorldAndPackedData[0].w, i.tangentToWorldAndPackedData[1].w, i.tangentToWorldAndPackedData[2].w);
	s.alpha = sos.Alpha;

	fragCameraAngularFading(s.normalWorld, s.eyeVec);

    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

	half4 c = 0.0;

#if !defined(_DISABLE_LIGHTING)
	ShadowContext shadowContext = InitShadowContext();

	half3 subsurfaceScatteringColor = readTexture(_EmissionMap, i).a * _SubsurfaceScatteringColor;

	// directional lights count
	for (int lightIndex = 0; lightIndex < _DirectionalLightsCount; ++lightIndex)
	{
		DeepLight light = GetLight(lightIndex);
		half grayscale = dot(light.color, half3(0.3, 0.59, 0.11));
		light.color = lerp(light.color, grayscale, _LightDesaturation);
		light.dir = lerp(light.dir, s.normalWorld, _LightingSoftness);
		c.rgb += EvaluateDirectionalLight(s, light, lightIndex, shadowContext, subsurfaceScatteringColor);
	}

	int pixelLightCount = GetPixelLightCount();
	for (int lightIndex2 = 0; lightIndex2 < pixelLightCount; ++lightIndex2)
	{
		int realLightIndex = _LightIndexBuffer[unity_LightIndicesOffsetAndCount.x + lightIndex2];

		DeepLight light = GetLight(realLightIndex);
		half grayscale = dot(light.color, half3(0.3, 0.59, 0.11));
		light.color = lerp(light.color, grayscale, _LightDesaturation);
		c.rgb += EvaluatePunctualLight(s, light, realLightIndex, shadowContext, subsurfaceScatteringColor);
	}

    UnityLight mainLight = DummyLight ();
	half atten = 1;

    half occlusion = sos.Occlusion;
    UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, mainLight);

    c += UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect);
#endif

    c.rgb += sos.Emission;

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
	float dist = UNITY_Z_0_FAR_FROM_CLIPSPACE(i.fogCoord);

#if !defined(_DISABLE_LIGHTING)
	DEEP_APPLY_FOG(i.fogCoord, c.rgb);
#else
	DEEP_APPLY_FOG_COLOR(i.fogCoord, c.rgb, unity_FogColor * dot(c.rgb, 0.33333333));
#endif
	
	//s.alpha = lerp(0.0, s.alpha, unityFogFactor);

#if !defined(_MASK_UNDERWATER)
	half underwaterMask = tex2Dproj(_UnderwaterMask, i.grabPassPosition);
#endif

	c.a = s.alpha;
	c = lerp(c, 0.0, underwaterMask * (1.0 - exp(dist * float4(-0.2262118, -0.0260612, -0.0117647, -0.0117647))));
	s.alpha = c.a;
	outFog = half4(1.0 - unityFogFactor.xxx, s.alpha);
#else
	outFog = half4(0.0, 0.0, 0.0, s.alpha);
#endif

	outColor = OutputForward(c, s.alpha);
	
}
// SRP END ----

void fragDeferred (VertexOutputForwardBase i,
	out half4 outGBuffer0 : SV_Target0,
	out half4 outGBuffer1 : SV_Target1,
	out half4 outGBuffer2 : SV_Target2,
	out half4 outEmission : SV_Target3)          // RT3: emission (rgb), --unused-- (a)) : SV_Target
{
#if _MASK_UNDERWATER
	half underwaterMask = tex2Dproj(_UnderwaterMask, i.grabPassPosition);
	clip(underwaterMask * _UnderwaterMaskFactors.x + _UnderwaterMaskFactors.y);
#endif

    //UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

    //FRAGMENT_SETUP(s)
	FragmentCommonData s;
	SurfaceOutputStandard sos;
	surf(i, sos);
	s.smoothness = sos.Smoothness;
	s.normalWorld = PerPixelWorldNormal(sos.Normal, i.tangentToWorldAndPackedData);
	s.diffColor = DiffuseAndSpecularFromMetallic(sos.Albedo, sos.Metallic, /*out*/ s.specColor, /*out*/ s.oneMinusReflectivity);
	s.eyeVec = NormalizePerPixelNormal(i.eyeVec);
	s.posWorld = half3(i.tangentToWorldAndPackedData[0].w, i.tangentToWorldAndPackedData[1].w, i.tangentToWorldAndPackedData[2].w);
	s.alpha = sos.Alpha;

    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

	half4 c = 0.0;

	UnityLight mainLight = DummyLight();
	half atten = 1;

	half occlusion = sos.Occlusion;
	UnityGI gi = FragmentGI(s, occlusion, i.ambientOrLightmapUV, atten, mainLight);

	c += UNITY_BRDF_PBS(s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect);

    c.rgb += sos.Emission;

	outGBuffer0 = half4(s.diffColor.rgb, 1.0);

    // RT1: spec color (rgb), smoothness (a) - sRGB rendertarget
    outGBuffer1 = half4(s.specColor, s.smoothness);

    // RT2: normal (rgb), --unused, very low precision-- (a)
    outGBuffer2 = half4(s.normalWorld * 0.5f + 0.5f, 1.0f);

	outEmission = half4(c.rgb, 1.0);
}

#endif // UNITY_STANDARD_CORE_INCLUDED
