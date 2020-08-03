// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced '_CameraToWorld' with 'unity_CameraToWorld'

Shader "Hidden/PlayWay Water-Internal-SRP-DeferredReflections" {
Properties {
	_LightAsQuad("", Float) = 0
	_SrcBlend("", Float) = 1
	_DstBlend("", Float) = 1
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
		Ref 8
		ReadMask 8
		WriteMask 8
		Comp Equal
	}

	ZWrite Off
	ZTest [_CompareFunc]
	Cull [_CullMode]
	Blend SrcAlpha OneMinusSrcAlpha
CGPROGRAM
#pragma target 3.0
#pragma vertex vert
#pragma fragment frag

#include "UnityCG.cginc"
#include "UnityDeferredLibrary.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityStandardBRDF.cginc"
#include "UnityPBSLighting.cginc"
#include "../Includes/WaterLib.cginc"

sampler2D _CameraGBufferTexture0;
sampler2D _WaterGBuffer1;
sampler2D _WaterGBuffer2;
sampler2D_float _WaterDepthTexture;
sampler2D _WaterBuffer;
sampler2D _GlobalWaterLookupTex;
sampler2D _AmbientOcclusionTexture;
half4	  _AmbientOcclusionParam;

UNITY_DECLARE_TEXCUBE(custom_SpecCube0);

CBUFFER_START(CustomReflectionProbes)
    float4 custom_SpecCube0_BoxMax;
    float4 custom_SpecCube0_BoxMin;
    float4 custom_SpecCube0_ProbePosition;
	float4 custom_SpecCube1_ProbePosition;
    half4  custom_SpecCube0_HDR;
CBUFFER_END

half4 BRDF1_Unity_PBS_WaterDeferred(half3 diffColor, half3 specColor, half oneMinusReflectivity, half oneMinusRoughness, half refractivity,
	half3 normal, half3 viewDir, half2 uv,
	UnityLight light, UnityIndirect gi, half atten, half refractionDistortion, bool isBack)
{
	//oneMinusRoughness *= _LightSmoothnessMul;

	half roughness = 1 - oneMinusRoughness;
	half3 halfDir = normalize(light.dir + viewDir);

	half nl = light.ndotl;
	half nh = BlinnTerm(normal, halfDir);
	half nv = DotClamped(normal, viewDir);
	half lv = DotClamped(light.dir, viewDir);
	half lh = DotClamped(light.dir, halfDir);

#if defined(POINT) || defined(SPOT) || defined(POINT_COOKIE)
	//nl = (nl + _MainWaterWrapSubsurfaceScatteringPack.z) * _MainWaterWrapSubsurfaceScatteringPack.w;
#else
	//nl = (nl + _MainWaterWrapSubsurfaceScatteringPack.x) * _MainWaterWrapSubsurfaceScatteringPack.y;
#endif

#if 0 // UNITY_BRDF_GGX - I'm not sure when it's set, but we don't want this in the case of water
	half V = SmithGGXVisibilityTerm(nl, nv, roughness);
	half D = GGXTerm(nh, roughness);
#else
	half V = SmithBeckmannVisibilityTerm(nl, nv, roughness);
	half D = NDFBlinnPhongNormalizedTerm(nh, RoughnessToSpecPower(roughness));
#endif

	half nlPow5 = Pow5(1 - nl);
	half nvPow5 = Pow5(1 - nv);
	half Fd90 = 0.5 + 2 * lh * lh * roughness;
	half disneyDiffuse = (1 + (Fd90 - 1) * nlPow5) * (1 + (Fd90 - 1) * nvPow5);

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

	half grazingTerm = saturate(oneMinusRoughness + (1 - oneMinusReflectivity));
	half3 fresnel = WaterFresnelLerp(specColor, grazingTerm, nv, isBack);

	half3 color = lerp(diffColor * light.color * diffuseTerm * atten, 0, refractivity)
		+ specularTerm * light.color * WaterFresnelTerm(specColor, lh) * atten
		+ surfaceReduction * gi.specular * fresnel;

	half ao = tex2D(_AmbientOcclusionTexture, uv);
	color *= lerp(1.0, ao, _AmbientOcclusionParam.w);		// w = direct lighting occlusion

	return half4(color, 1);
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
	float depth = SAMPLE_DEPTH_TEXTURE(_WaterDepthTexture, uv);
	depth = Linear01Depth (depth);
	float4 viewPos = float4(i.ray * depth,1);
	float3 worldPos = mul (unity_CameraToWorld, viewPos).xyz;

	half4 gbuffer0 = tex2D (_CameraGBufferTexture0, uv);
	half4 gbuffer1 = tex2D (_WaterGBuffer1, uv);
	half4 gbuffer2 = tex2D (_WaterGBuffer2, uv);
	half4 waterData = tex2D(_WaterBuffer, uv);

	bool isBack = gbuffer2.a < 0.5;

	half4 lookup1 = tex2Dlod(_GlobalWaterLookupTex, half4(waterData.a, 0.375, 0, 0));
	half3 reflectionColor = lookup1.rgb;

	half3 specColor = gbuffer1.rgb;
	half oneMinusRoughness = gbuffer1.a;
	half3 worldNormal = gbuffer2.rgb * 2 - 1;
	float3 eyeVec = normalize(worldPos - _WorldSpaceCameraPos);
	worldNormal = normalize(worldNormal);
	
	half oneMinusReflectivity = 1 - SpecularStrength(specColor.rgb);
	half occlusion = 0.4 + 0.6 * waterData.g;		// waterData.g;

	half3 worldNormalRefl = reflect(eyeVec, worldNormal);

	occlusion *= lerp(0.29, 1.0, saturate((worldNormalRefl.y + 0.2 * 0.85) / (2.0 * 0.2)));			// sea self-reflection

	if (worldNormalRefl.y < 0.05)
	{
		//occlusion *= 1.0 + max(-0.5, worldNormalRefl.y - 0.1) * 0.5;
		worldNormalRefl.y = 0.05 + (0.05 * 0.1) - worldNormalRefl.y * 0.1;
		worldNormalRefl = normalize(worldNormalRefl);
		//worldNormalRefl.y = 0.05;
	}

	//worldNormalRefl.y = abs(worldNormalRefl.y);

	float blendDistance = custom_SpecCube1_ProbePosition.w; // will be set to blend distance for this probe

	#if UNITY_SPECCUBE_BOX_PROJECTION
		// For box projection, use expanded bounds as they are rendered; otherwise
		// box projection artifacts when outside of the box.
		float4 boxMin = custom_SpecCube0_BoxMin - float4(blendDistance,blendDistance,blendDistance,0);
		float4 boxMax = custom_SpecCube0_BoxMax + float4(blendDistance,blendDistance,blendDistance,0);
		half3 worldNormal0 = BoxProjectedCubemapDirection (worldNormalRefl, worldPos, custom_SpecCube0_ProbePosition, boxMin, boxMax);
	#else
		half3 worldNormal0 = worldNormalRefl;
	#endif

	Unity_GlossyEnvironmentData g;
	g.roughness		= 1 - oneMinusRoughness;
	g.reflUVW		= worldNormal0;

	if (isBack)
		g.roughness = lerp(g.roughness, 1.0, 0.75);

	half3 env0 = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(custom_SpecCube0), custom_SpecCube0_HDR, g);

	UnityLight light;
	light.color = 0;
	light.dir = 0;
	light.ndotl = 0;

	UnityIndirect ind;
	ind.diffuse = 0;
	ind.specular = env0 * occlusion;

	if (isBack)
		ind.specular *= 0.4;

	half3 rgb = BRDF1_Unity_PBS_WaterDeferred(0, specColor, oneMinusReflectivity, oneMinusRoughness, 1.0, worldNormal, -eyeVec, uv, light, ind, 0.0, 0.0, false).rgb;

	// Calculate falloff value, so reflections on the edges of the probe would gradually blend to previous reflection.
	// Also this ensures that pixels not located in the reflection probe AABB won't
	// accidentally pick up reflections from this probe.
	half3 distance = distanceFromAABB(worldPos, custom_SpecCube0_BoxMin.xyz, custom_SpecCube0_BoxMax.xyz);
	half falloff = saturate(1.0 - length(distance)/blendDistance);
	rgb *= gbuffer0.a;
	return half4(rgb * reflectionColor, falloff);
}

ENDCG
}

// Adds reflection buffer to the lighting buffer
Pass
{
	ZWrite Off
	ZTest Always
	Blend [_SrcBlend] [_DstBlend]

	CGPROGRAM
		#pragma target 3.0
		#pragma vertex vert
		#pragma fragment frag
		#pragma multi_compile ___ UNITY_HDR_ON

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
			#ifdef UNITY_HDR_ON
			return c;
			#else
			return exp2(-c);
			#endif

		}
	ENDCG
}

}
Fallback Off
}
