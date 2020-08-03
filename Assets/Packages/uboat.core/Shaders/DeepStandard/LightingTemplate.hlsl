#ifndef __DEFERREDLIGHTINGTEMPLATE_H__
#define __DEFERREDLIGHTINGTEMPLATE_H__


#include "UnityCG.cginc"
#include "UnityStandardBRDF.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityPBSLighting.cginc"

//uniform uint g_nNumDirLights;

//---------------------------------------------------------------------------------------------------------------------------------------------------------
// TODO:  clean up.. -va
#define MAX_SHADOW_LIGHTS 10
#define MAX_SHADOWMAP_PER_LIGHT 6
#define MAX_DIRECTIONAL_SPLIT  4

#define CUBEMAPFACE_POSITIVE_X 0
#define CUBEMAPFACE_NEGATIVE_X 1
#define CUBEMAPFACE_POSITIVE_Y 2
#define CUBEMAPFACE_NEGATIVE_Y 3
#define CUBEMAPFACE_POSITIVE_Z 4
#define CUBEMAPFACE_NEGATIVE_Z 5

#define SHADOW_USE_VIEW_BIAS_SCALING            1   // Enable view bias scaling to mitigate light leaking across edges. Uses the light vector if SHADOW_USE_ONLY_VIEW_BASED_BIASING is defined, otherwise uses the normal.
// Note: Sample biasing work well but is very costly in term of VGPR, disable it for now
#define SHADOW_USE_SAMPLE_BIASING               0   // Enable per sample biasing for wide multi-tap PCF filters. Incompatible with SHADOW_USE_ONLY_VIEW_BASED_BIASING.
#define SHADOW_USE_DEPTH_BIAS                   0   // Enable clip space z biasing

sampler2D _CameraGBufferTexture0;
sampler2D _CameraGBufferTexture1;
sampler2D _CameraGBufferTexture2;

sampler2D _CausticsMap;
sampler2D _CausticsDistortionMap;
sampler2D _UnderwaterMask;
sampler2D _WaterlessDepthTexture;
sampler2D _WaterDepthTexture;
float	  _CausticsMapKey;
float	  _CausticsMultiplier;
float4x4  _CausticsMapProj;
float4	  _CausticsOffsetScale;
float4	  _CausticsOffsetScale2;
half4	  _AbsorptionColor;
sampler2D _TotalDisplacementMap;
float4	  _LocalMapsCoords;
float	  _LightIndexForShadowMatrixArray;

sampler2D _AmbientOcclusionTexture;
half4	  _AmbientOcclusionParam;

/*#if defined(SHADER_API_D3D11)
#	include "CoreRP/ShaderLibrary/API/D3D11.hlsl"
#elif defined(SHADER_API_PSSL)
#	include "CoreRP/ShaderLibrary/API/PSSL.hlsl"
#elif defined(SHADER_API_XBOXONE)
#	include "CoreRP/ShaderLibrary/API/D3D11.hlsl"
#	include "CoreRP/ShaderLibrary/API/D3D11_1.hlsl"
#elif defined(SHADER_API_METAL)
#	include "CoreRP/ShaderLibrary/API/Metal.hlsl"
#else
#	error unsupported shader api
#endif
#include "CoreRP/ShaderLibrary/API/Validate.hlsl"*/
#include "CoreRP/ShaderLibrary/Common.hlsl"
#include "ShadowDispatch.hlsl"
 
#if UNITY_VERSION >= 550
	#define conditionalTex2D tex2D
#else
	#define conditionalTex2D tex2Dlod
#endif

/*float3 ApplyWaterInfluence(float2 uv, float3 wpos)
{
#if defined(WATER_BUFFERS_ENABLED) && (defined(DIRECTIONAL) || defined (DIRECTIONAL_COOKIE))
	UNITY_BRANCH
	if(abs(_LightPos.y - 6.137) < 0.001)
	{
		// apply directional light caustics
		float4 uvlod = float4(uv, 0.0, 0.0);
		float waterDepth = SAMPLE_DEPTH_TEXTURE_LOD(_WaterDepthTexture, uvlod);
		float depth = SAMPLE_DEPTH_TEXTURE_LOD(_WaterlessDepthTexture, uvlod);
		half underwaterMask = tex2Dlod(_UnderwaterMask, uvlod).r;

#if UNITY_VERSION >= 550
		waterDepth = lerp(waterDepth, 1.0, underwaterMask);
		if (waterDepth > depth)
#else
		waterDepth *= 1.0 - underwaterMask;
		if(waterDepth < depth)
#endif
		{
			half2 localUv = uv * _LocalMapsCoords.zz + _LocalMapsCoords.xy;
			half waterElevation = tex2Dlod(_TotalDisplacementMap, half4(localUv, 0, 0)).y;

			float4 uvx = mul(_CausticsMapProj, float4(wpos, 1));
			uvx.xy = (uvx.xy * float2(0.5, -0.5)) + 0.5;
			uvx.zw = 0;

			half2 distort = tex2Dlod(_CausticsDistortionMap, uvx);
			float4 uvx2 = uvx;
			uvx2.xy += distort * _CausticsOffsetScale.ww;
			uvx2.xy = uvx2.xy * _CausticsOffsetScale.zz + _CausticsOffsetScale.xy;
			half caustic = tex2Dlod(_CausticsMap, uvx2).r;

			uvx2.xy = uvx.xy;
			uvx2.xy += distort.yx * _CausticsOffsetScale2.ww;
			uvx2.xy = uvx2.xy * _CausticsOffsetScale2.zz + _CausticsOffsetScale2.xy;
			caustic += tex2Dlod(_CausticsMap, uvx2).r;

			half depthDelta = LinearEyeDepth(depth) - LinearEyeDepth(waterDepth);

			return lerp(1, caustic * _CausticsMultiplier * exp(_AbsorptionColor * 0.15 * min(wpos.y - waterElevation, 0.0)), saturate(depthDelta * 0.1));
		}
	}
	else
	{
		// apply light fade under water
		float4 uvlod = float4(uv, 0.0, 0.0);
		float waterDepth = SAMPLE_DEPTH_TEXTURE_LOD(_WaterDepthTexture, uvlod);
		float depth = SAMPLE_DEPTH_TEXTURE_LOD(_WaterlessDepthTexture, uvlod);
		half underwaterMask = tex2Dlod(_UnderwaterMask, uvlod).r;

#if UNITY_VERSION >= 550
		waterDepth = lerp(waterDepth, 1.0, underwaterMask);
		if (waterDepth > depth)
#else
		waterDepth *= 1.0 - underwaterMask;
		if (waterDepth < depth)
#endif
		{
			half2 localUv = uv * _LocalMapsCoords.zz + _LocalMapsCoords.xy;
			half waterElevation = tex2Dlod(_TotalDisplacementMap, half4(localUv, 0, 0)).y;

			half depthDelta = LinearEyeDepth(depth) - LinearEyeDepth(waterDepth);

			return _CausticsMultiplier * lerp(1, exp(_AbsorptionColor * 0.15 * min(wpos.y - waterElevation, 0.0)), saturate(depthDelta * 0.1));
		}
	}
#endif

	return 1;
}*/

/*half4 CalculateLight (UnityLight light, float3 wpos, float atten, float3 diffuseColor, float occlusion, float4 specColor, float3 normalWorld)
{
	UnityStandardData data;

	data.diffuseColor = diffuseColor;
	data.occlusion = occlusion;
	data.specularColor = specColor.rgb;
	data.smoothness = specColor.a;
	data.normalWorld = normalWorld;

	ShadowContext shadowContext = InitShadowContext();


	float3 tolight = light.dir.xyz - wpos;
	half3 lightDir = normalize(tolight);

	if (_LightIndexForShadowMatrixArray >= 0)
#if defined (POINT) || defined (POINT_COOKIE)
		atten *= GetPunctualShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#elif defined (DIRECTIONAL) || defined(DIRECTIONAL_COOKIE)
		atten *= GetDirectionalShadowAttenuation(shadowContext, wpos, data.normalWorld, _LightIndexForShadowMatrixArray, lightDir, length(tolight));
#endif

	float3 atten3 = atten;// *ApplyWaterInfluence(uv, wpos);

	light.color.rgb *= atten3;

	float3 eyeDelta = wpos - _WorldSpaceCameraPos;
	float3 eyeVec = normalize(eyeDelta);
	half oneMinusReflectivity = 1 - SpecularStrength(data.specularColor.rgb);

	UnityIndirect ind;
	UNITY_INITIALIZE_OUTPUT(UnityIndirect, ind);
	ind.diffuse = 0;
	ind.specular = 0;

    half4 res = UNITY_BRDF_PBS (data.diffuseColor, data.specularColor, oneMinusReflectivity, data.smoothness, data.normalWorld, -eyeVec, light, ind);

	res.rgb *= lerp(1, occlusion, min(1.0, dot(eyeDelta, eyeDelta) / 32400) * 0.65);

	//half ao = tex2D(_AmbientOcclusionTexture, uv);
	//res.rgb *= lerp(1.0, ao, _AmbientOcclusionParam.w) / ao;		// w = direct lighting occlusion

	return res;
}*/

#endif
