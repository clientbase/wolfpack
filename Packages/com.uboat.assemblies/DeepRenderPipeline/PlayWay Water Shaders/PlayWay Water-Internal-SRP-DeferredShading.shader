// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/PlayWay Water-Internal-SRP-DeferredShading" {
Properties {
	_LightTexture0 ("", any) = "" {}
	_LightTextureB0 ("", 2D) = "" {}
	_ShadowMapTexture ("", any) = "" {}

	_SrcBlend ("", Float) = 1
	_DstBlend ("", Float) = 1
	_SrcABlend ("", Float) = 1
    _DstABlend ("", Float) = 1

    _CullMode ("", Float) = 0
    _CompareFunc ("", Float) = 0
}
SubShader {

// Pass 1: Lighting pass
//  LDR case - Lighting encoded into a subtractive ARGB8 buffer
//  HDR case - Lighting additively blended into floating point buffer
Pass {
	Stencil
	{
		Ref 8
		ReadMask 8
		WriteMask 8
		Comp Equal
	}

	ZWrite Off
	ZTest [_CompareFunc]
	Cull [_CullMode]
	Blend DstAlpha One, Zero One

HLSLPROGRAM
#pragma target 4.5
#pragma vertex vert
#pragma fragment frag
#pragma multi_compile_lightpass
#pragma multi_compile ___ UNITY_HDR_ON

#pragma exclude_renderers nomrt

#define _DEFERRED_SHADER 1

#include "UnityCG.cginc"
#include "UnityDeferredLibrary.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityStandardBRDF.cginc"
#include "../Includes/WaterLib.cginc"

#if defined(SHADER_API_D3D11)
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
#include "CoreRP/ShaderLibrary/API/Validate.hlsl"
#include "CoreRP/ShaderLibrary/Common.hlsl"
#include "ShadowDispatch.hlsl"

sampler2D _CameraGBufferTexture0;
sampler2D _WaterGBuffer1;
sampler2D _WaterGBuffer2;
sampler2D _WaterBuffer;
sampler2D _AmbientOcclusionTexture;
sampler2D _GlobalWaterLookupTex;
sampler2D_float _WaterDepthTexture;
half4	  _MainWaterWrapSubsurfaceScatteringPack;
float	  _LightIndexForShadowMatrixArray;
half4	  _AmbientOcclusionParam;
half	  _MaxSmoothness;

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

half4 BRDF1_Unity_PBS_WaterDeferred (half3 diffColor, half3 specColor, half oneMinusReflectivity, half oneMinusRoughness, half refractivity,
	half3 normal, half3 viewDir, half2 uv,
	UnityLight light, UnityIndirect gi, half atten, half refractionDistortion, bool isBack)
{
	//oneMinusRoughness *= _LightSmoothnessMul;

	half roughness = 1-oneMinusRoughness;
	half3 halfDir = normalize (light.dir + viewDir);

	half nl = light.ndotl;
	half nh = BlinnTerm (normal, halfDir);
	half nv = DotClamped (normal, viewDir);
	half lv = DotClamped (light.dir, viewDir);
	half lh = DotClamped (light.dir, halfDir);

#if 0 // UNITY_BRDF_GGX - I'm not sure when it's set, but we don't want this in the case of water
	half V = SmithGGXVisibilityTerm (nl, nv, roughness);
	half D = GGXTerm (nh, roughness);
#else
	half V = SmithBeckmannVisibilityTerm (nl, nv, roughness);
	half D = NDFBlinnPhongNormalizedTerm (nh, RoughnessToSpecPower (roughness));
#endif

	half nlPow5 = Pow5 (1-nl);
	half nvPow5 = Pow5 (1-nv);
	half Fd90 = 0.5 + 2 * lh * lh * roughness;
	half disneyDiffuse = (1 + (Fd90-1) * nlPow5) * (1 + (Fd90-1) * nvPow5);
	
	// HACK: theoretically we should divide by Pi diffuseTerm and not multiply specularTerm!
	// BUT 1) that will make shader look significantly darker than Legacy ones
	// and 2) on engine side "Non-important" lights have to be divided by Pi to in cases when they are injected into ambient SH
	// NOTE: multiplication by Pi is part of single constant together with 1/4 now

	half specularTerm = (V * D) * (1.0 / (4 * UNITY_PI));// Torrance-Sparrow model, Fresnel is applied later (for optimization reasons)
	if (IsGammaSpace())
		specularTerm = sqrt(max(1e-4h, specularTerm));
	specularTerm = max(0, specularTerm * nl);

#if defined(_SPECULARHIGHLIGHTS_OFF)
	specularTerm = 0.0;
#endif

	half diffuseTerm = disneyDiffuse * nl;

	half realRoughness = roughness*roughness;		// need to square perceptual roughness
	half surfaceReduction;
	if (IsGammaSpace()) surfaceReduction = 1.0 - 0.28*realRoughness*roughness;		// 1-0.28*x^3 as approximation for (1/(x^4+1))^(1/2.2) on the domain [0;1]
	else surfaceReduction = 1.0 / (realRoughness*realRoughness + 1.0);			// fade \in [0.5;1]

	if (isBack)
		specularTerm = 0;

	half waterSurfaceDepth = LinearEyeDepth(tex2D(_WaterDepthTexture, uv).r);

	half4 refractOffset = ComputeDistortOffset(normal, refractionDistortion);
	half4 refractCoord = half4(uv, 0, 0) + refractOffset;
	half centerSceneDepth = LinearEyeDepth(tex2Dlod(_WaterlessDepthTexture, refractCoord)) - waterSurfaceDepth;
	half distortScale = saturate(centerSceneDepth * 4);

	uv += refractOffset * distortScale;

	half3 depthFade;
	half sceneDepth = LinearEyeDepth(tex2D(_WaterlessDepthTexture, uv).r);
	depthFade = min(exp(-_AbsorptionColor * (sceneDepth - waterSurfaceDepth)), 1);
	
	half grazingTerm = saturate(oneMinusRoughness + (1-oneMinusReflectivity));

	half3 fresnel = WaterFresnelLerp(specColor, grazingTerm, nv, isBack);
	half3 refractedColor = gi.diffuse * (1.0 - fresnel) * (1.0 - depthFade*depthFade);
	half specularEnergyLossCorrectionFactor = 1.55;

	half3 color = lerp(diffColor * light.color * diffuseTerm, refractedColor, lerp(refractivity, 1.0, 0.3))
		+ specularTerm * light.color * WaterFresnelTerm(specColor, lh) * specularEnergyLossCorrectionFactor * atten
		+ surfaceReduction * gi.specular * fresnel;

	half ao = tex2D(_AmbientOcclusionTexture, uv);
	color *= lerp(1.0, ao, _AmbientOcclusionParam.w);		// w = direct lighting occlusion

	return half4(color, 1);
}

half4 BRDF1_Unity_PBS_WaterDeferred_Back (half3 diffColor, half3 specColor, half oneMinusReflectivity, half oneMinusRoughness,
	half3 normal, half3 viewDir,
	UnityLight light, UnityIndirect gi, half atten)
{
	//oneMinusRoughness *= _LightSmoothnessMul;

	half roughness = 1-oneMinusRoughness;
	half3 halfDir = normalize (light.dir + viewDir);

	half nl = light.ndotl;
	half nh = BlinnTerm (normal, halfDir);
	half nv = DotClamped (normal, viewDir);
	half lv = DotClamped (light.dir, viewDir);
	half lh = DotClamped (light.dir, halfDir);

#if defined(POINT) || defined(SPOT) || defined(POINT_COOKIE)
	nl = (nl + _MainWaterWrapSubsurfaceScatteringPack.z) * _MainWaterWrapSubsurfaceScatteringPack.w;
#else
	nl = (nl + _MainWaterWrapSubsurfaceScatteringPack.x) * _MainWaterWrapSubsurfaceScatteringPack.y;
#endif

#if 0 // UNITY_BRDF_GGX - I'm not sure when it's set, but we don't want this in the case of water
	half V = SmithGGXVisibilityTerm (nl, nv, roughness);
	half D = GGXTerm (nh, roughness);
#else
	half V = SmithBeckmannVisibilityTerm (nl, nv, roughness);
	half D = NDFBlinnPhongNormalizedTerm (nh, RoughnessToSpecPower (roughness));
#endif

	half nlPow5 = Pow5 (1-nl);
	half nvPow5 = Pow5 (1-nv);
	half Fd90 = 0.5 + 2 * lh * lh * roughness;
	half disneyDiffuse = (1 + (Fd90-1) * nlPow5) * (1 + (Fd90-1) * nvPow5);
	
	// HACK: theoretically we should divide by Pi diffuseTerm and not multiply specularTerm!
	// BUT 1) that will make shader look significantly darker than Legacy ones
	// and 2) on engine side "Non-important" lights have to be divided by Pi to in cases when they are injected into ambient SH
	// NOTE: multiplication by Pi is part of single constant together with 1/4 now

	half specularTerm = (V * D) * (1.0 / (4 * UNITY_PI));// Torrance-Sparrow model, Fresnel is applied later (for optimization reasons)
	if (IsGammaSpace())
		specularTerm = sqrt(max(1e-4h, specularTerm));
	specularTerm = max(0, specularTerm * nl);

#if defined(_SPECULARHIGHLIGHTS_OFF)
	specularTerm = 0.0;
#endif

	half diffuseTerm = disneyDiffuse * nl;

	half realRoughness = roughness*roughness;		// need to square perceptual roughness
	half surfaceReduction;
	if (IsGammaSpace()) surfaceReduction = 1.0 - 0.28*realRoughness*roughness;		// 1-0.28*x^3 as approximation for (1/(x^4+1))^(1/2.2) on the domain [0;1]
	else surfaceReduction = 1.0 / (realRoughness*realRoughness + 1.0);			// fade \in [0.5;1]

	half3 depthFade;
	
	half grazingTerm = saturate(oneMinusRoughness + (1-oneMinusReflectivity));
	half3 color = diffColor * (gi.diffuse + light.color * diffuseTerm);

	return half4(color, 1);
}
		
half4 CalculateLight (unity_v2f_deferred i)
{
	float3 wpos;
	float2 uv;
	float atten, fadeDist;
	float atten2 = 1.0;
	UnityLight light;
	UNITY_INITIALIZE_OUTPUT(UnityLight, light);
	UnityDeferredCalculateLightParams (i, wpos, uv, light.dir, atten, fadeDist);

	half4 gbuffer0 = tex2D (_CameraGBufferTexture0, uv);
	half4 gbuffer1 = tex2D (_WaterGBuffer1, uv);
	half4 gbuffer2 = tex2D (_WaterGBuffer2, uv);
	half4 waterData = tex2D(_WaterBuffer, uv);

	half4 lookup3 = tex2Dlod(_GlobalWaterLookupTex, half4(waterData.a, 0.875, 0, 0));
	half lightSmoothnessMul = lookup3.a;

#if defined(DIRECTIONAL) || defined (DIRECTIONAL_COOKIE)
	half4 lookup2 = tex2Dlod(_GlobalWaterLookupTex, half4(waterData.a, 0.625, 0, 0));
	lightSmoothnessMul *= lookup2.a;
#endif

	half3 baseColor = gbuffer0;
	half3 specColor = gbuffer1.rgb;
	half refractivity = waterData.r;
	half occlusion = waterData.g;
	half oneMinusRoughness = gbuffer1.a * lightSmoothnessMul;
	oneMinusRoughness = min(oneMinusRoughness, _MaxSmoothness);
	half3 normalWorld = gbuffer2.rgb * 2 - 1;
	normalWorld = normalize(normalWorld);
	float3 eyeVec = normalize(wpos - _WorldSpaceCameraPos);
	half oneMinusReflectivity = 1 - SpecularStrength(specColor.rgb);
	light.ndotl = LambertTerm(normalWorld, light.dir);

	ShadowContext shadowContext = InitShadowContext();
	float3 tolight = _LightPos.xyz - wpos;

	if (_LightIndexForShadowMatrixArray >= 0)
#if defined (POINT) || defined (POINT_COOKIE)
		atten2 *= GetPunctualShadowAttenuation(shadowContext, wpos, normalWorld, _LightIndexForShadowMatrixArray, light.dir, length(tolight));
#elif defined(SPOT) || defined (SPOT_COOKIE)
		atten2 *= GetPunctualShadowAttenuation(shadowContext, wpos, normalWorld, _LightIndexForShadowMatrixArray, light.dir, length(tolight));
#elif defined (DIRECTIONAL) || defined(DIRECTIONAL_COOKIE)
		atten2 *= GetDirectionalShadowAttenuation(shadowContext, wpos, normalWorld, _LightIndexForShadowMatrixArray, light.dir, length(tolight));
#endif

	atten *= lerp(0.7, 1.0, atten2);

	light.color = _LightColor.rgb * atten;

	bool isBack = gbuffer2.a < 0.5;

	UnityIndirect ind;
	UNITY_INITIALIZE_OUTPUT(UnityIndirect, ind);
	ind.diffuse = 0;
	ind.specular = 0;

	half4 lookup1 = tex2Dlod(_GlobalWaterLookupTex, half4(waterData.a, 0.375, 0, 0));
	half forwardScatterIntensity = lookup1.a;

	half4 lookup0 = tex2Dlod(_GlobalWaterLookupTex, half4(waterData.a, 0.125, 0, 0));
	half3 absorptionColor = lookup0.rgb;
	half refractionDistortion = lookup0.a;
	ind.diffuse = baseColor * ComputeDepthColorv5(absorptionColor, eyeVec, light.color, light.dir, normalWorld, occlusion) * forwardScatterIntensity;

	half4 res = BRDF1_Unity_PBS_WaterDeferred (baseColor, specColor, oneMinusReflectivity, oneMinusRoughness, refractivity, normalWorld, -eyeVec, uv, light, ind, atten2, refractionDistortion, isBack);
	res.rgb *= gbuffer0.a;
	return res;
}

#ifdef UNITY_HDR_ON
half4
#else
fixed4
#endif
frag (unity_v2f_deferred i) : SV_Target
{
	half4 c = CalculateLight(i);
	#ifdef UNITY_HDR_ON
	return c;
	#else
	return exp2(-c);
	#endif
}

ENDHLSL
}


// Pass 2: Final decode pass.
// Used only with HDR off, to decode the logarithmic buffer into the main RT
Pass {
	ZTest Always Cull Off ZWrite Off
	Stencil {
		ref [_StencilNonBackground]
		readmask [_StencilNonBackground]
		// Normally just comp would be sufficient, but there's a bug and only front face stencil state is set (case 583207)
		compback equal
		compfront equal
	}

HLSLPROGRAM
#pragma target 3.0
#pragma vertex vert
#pragma fragment frag
#pragma exclude_renderers nomrt

#include "UnityCG.cginc"

sampler2D _LightBuffer;
struct v2f {
	float4 vertex : SV_POSITION;
	float2 texcoord : TEXCOORD0;
};

v2f vert (float4 vertex : POSITION, float2 texcoord : TEXCOORD0)
{
	v2f o;
	o.vertex = UnityObjectToClipPos(vertex);
	o.texcoord = texcoord.xy;
	return o;
}

fixed4 frag (v2f i) : SV_Target
{
	return -log2(tex2D(_LightBuffer, i.texcoord));
}
ENDHLSL
}

}
Fallback Off
}
