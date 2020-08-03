#ifndef DEEP_STANDARD_INCLUDED
#define DEEP_STANDARD_INCLUDED

#include "UnityCG.cginc"
#include "PlayWay Water/Shaders/Includes/EarthCurvature.cginc"

half _FogMaxValue;

#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
    #if (SHADER_TARGET < 30) || defined(SHADER_API_MOBILE)
        // mobile or SM2.0: fog factor was already calculated per-vertex, so just lerp the color
        #define DEEP_APPLY_FOG_COLOR(coord,col,fogCol) UNITY_FOG_LERP_COLOR(col,fogCol,(coord).x)
    #else
        // SM3.0 and PC/console: calculate fog factor and lerp fog color
        #define DEEP_APPLY_FOG_COLOR(coord,col,fogCol) UNITY_CALC_FOG_FACTOR((coord).x); unityFogFactor = lerp(1.0, unityFogFactor, _FogMaxValue); UNITY_FOG_LERP_COLOR(col,fogCol,unityFogFactor)
    #endif
#else
    #define DEEP_APPLY_FOG_COLOR(coord,col,fogCol)
#endif

#ifdef UNITY_PASS_FORWARDADD
    #define DEEP_APPLY_FOG(coord,col) DEEP_APPLY_FOG_COLOR(coord,col,fixed4(0,0,0,0))
#else
    #define DEEP_APPLY_FOG(coord,col) DEEP_APPLY_FOG_COLOR(coord,col,unity_FogColor)
#endif

#if defined(_DISSOLVE)
	#define DISSOLVE_MASK(x) DissolveMask(x)

	sampler2D _DissolveMask;
	half _DissolveMaskScale;
#else
	#define DISSOLVE_MASK(x) 
#endif

#if defined(_SIMPLE_WATER)
	half _PerlinIntensity;
	float _ClipHeight;
#endif

void DissolveMask(half2 uv)
{
#if defined(_DISSOLVE)
	half mask = tex2D(_DissolveMask, uv * _DissolveMaskScale);
	clip(mask - (1.0 - _Color.a));
#endif
}

#if defined(_DEEP_PIPELINE)
	#if defined(USING_STEREO_MATRICES)
		// there is no support for stereo in our pipeline, these arrays are not being set
		float4x4 _StereoNonJitteredVP[2];
		float4x4 _StereoPreviousVP[2];
	#else
		float4x4 _NonJitteredViewProjMatrix;
		float4x4 _PrevViewProjMatrix;
	#endif

	CBUFFER_START(UnityVelocityPass)
		float4x4 unity_MatrixPreviousM;

		//X : Use last frame positions (right now skinned meshes are the only objects that use this
		//Y : Force No Motion
		//Z : Z bias value
		float4 unity_MotionVectorsParams;
	CBUFFER_END

	#define _HasLastPositionData unity_MotionVectorsParams.x > 0
	#define _ForceNoMotion unity_MotionVectorsParams.y
	#define _MotionVectorDepthBias unity_MotionVectorsParams.z
#else
	#if defined(USING_STEREO_MATRICES)
		float4x4 _StereoNonJitteredVP[2];
		float4x4 _StereoPreviousVP[2];
	#else
		float4x4 _NonJitteredVP;
		float4x4 _PreviousVP;
	#endif

	CBUFFER_START(UnityVelocityPass)
		float4x4 _PreviousM;

		bool _HasLastPositionData;
		bool _ForceNoMotion;
		float _MotionVectorDepthBias;
	CBUFFER_END

	#define _NonJitteredViewProjMatrix _NonJitteredVP
	#define _PrevViewProjMatrix _PreviousVP
	#define unity_MatrixPreviousM _PreviousM
#endif


struct MotionVectorData
{
	UNITY_POSITION(pos);
	float4 transferPos : TEXCOORD0;
	float4 transferPosOld : TEXCOORD1;
	float2 tex : TEXCOORD2;
	UNITY_VERTEX_OUTPUT_STEREO
};

struct MotionVertexInput
{
	float4 vertex : POSITION;
	float3 oldPos : TEXCOORD4;
	float2 uv0 : TEXCOORD0;
	float2 uv1 : TEXCOORD1;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

half _CameraIndex;

MotionVectorData VertMotionVectors(MotionVertexInput v)
{
	MotionVectorData o;
	UNITY_SETUP_INSTANCE_ID(v);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	float4 posWorld = mul(unity_ObjectToWorld, v.vertex);

	if(_CameraIndex == 1)
		posWorld = CompensateForEarthCurvature(posWorld);

#if defined(_SIMPLE_WATER)
	v.vertex.y -= max(0.0, posWorld.y - _ClipHeight);
#endif

	o.pos = mul(UNITY_MATRIX_VP, posWorld);

	// this works around an issue with dynamic batching
	// potentially remove in 5.4 when we use instancing
/*#if defined(UNITY_REVERSED_Z)
	o.pos.z -= _MotionVectorDepthBias * o.pos.w;
#else
	o.pos.z += _MotionVectorDepthBias * o.pos.w;
#endif*/

	o.tex = TRANSFORM_TEX(((_UVSec == 0) ? v.uv0 : v.uv1), _DetailAlbedoMap);

	float3 delta = v.vertex.xyz - v.oldPos;

	if (_CameraIndex == 1)
	{
	#if defined(USING_STEREO_MATRICES)
		o.transferPos = mul(_StereoNonJitteredVP[unity_StereoEyeIndex], CompensateForEarthCurvature(mul(unity_ObjectToWorld, v.vertex)));
		o.transferPosOld = mul(_StereoPreviousVP[unity_StereoEyeIndex], CompensateForEarthCurvature(mul(unity_MatrixPreviousM, _HasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex)));
	#else
		o.transferPos = mul(_NonJitteredViewProjMatrix, CompensateForEarthCurvature(mul(unity_ObjectToWorld, v.vertex)));
		o.transferPosOld = mul(_PrevViewProjMatrix, CompensateForEarthCurvature(mul(unity_MatrixPreviousM, _HasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex)));
	#endif
	}
	else
	{
	#if defined(USING_STEREO_MATRICES)
		o.transferPos = mul(_StereoNonJitteredVP[unity_StereoEyeIndex], mul(unity_ObjectToWorld, v.vertex));
		o.transferPosOld = mul(_StereoPreviousVP[unity_StereoEyeIndex], mul(unity_MatrixPreviousM, _HasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex));
	#else
		o.transferPos = mul(_NonJitteredViewProjMatrix, mul(unity_ObjectToWorld, v.vertex));
		o.transferPosOld = mul(_PrevViewProjMatrix, mul(unity_MatrixPreviousM, _HasLastPositionData && dot(delta, delta) < 0.2 ? float4(v.oldPos, 1) : v.vertex));
	#endif
	}

	return o;
}

half4 FragMotionVectors(MotionVectorData i) : SV_Target
{
	DISSOLVE_MASK(i.tex.xy);

	float3 hPos = (i.transferPos.xyz / i.transferPos.w);
	float3 hPosOld = (i.transferPosOld.xyz / i.transferPosOld.w);

	// V is the viewport position at this pixel in the range 0 to 1.
	float2 vPos = (hPos.xy + 1.0f) / 2.0f;
	float2 vPosOld = (hPosOld.xy + 1.0f) / 2.0f;

#if UNITY_UV_STARTS_AT_TOP
	vPos.y = 1.0 - vPos.y;
	vPosOld.y = 1.0 - vPosOld.y;
#endif
	half2 uvDiff = vPos - vPosOld;

#if defined(_DEEP_PIPELINE)
	return lerp(0, half4(uvDiff, 0, 1), (half)_ForceNoMotion);		// in SRP 0 means no motion instead of 1
#else
	return lerp(half4(uvDiff, 0, 1), 0, (half)_ForceNoMotion);
#endif
}

half _UVWetnessMap;

#if defined(_DAMAGE_MAP)
sampler2D _DamageMask;
sampler2D _DamageMap;

void ApplyDamage(float2 uv0, float2 uv2, inout FragmentCommonData s)
{
	half damageMask = tex2D(_DamageMask, uv0);
	half surfaceCondition = min(1.0, damageMask * 0.025 + tex2D(_DamageMap, uv2));
	clip(surfaceCondition - 0.02);

	s.diffColor *= (0.02 + surfaceCondition * 0.98);
	s.specColor *= surfaceCondition;
	s.smoothness *= surfaceCondition;
}
#else
#define ApplyDamage(a, b, c) 
#endif

#if defined(_WETNESS_SUPPORT_ON)
sampler2D _WetnessMap;
half4 _WetnessBiasScale;

void ApplyWetness(float2 uv2, inout FragmentCommonData s)
{
	half wetness = min(1.0, dot(_WetnessBiasScale.xyz * tex2D(_WetnessMap, uv2).rgb + _WetnessBiasScale.www, 1));

	s.diffColor *= 0.55 + 0.45 * max(1.0 - wetness, 1.0 - s.specColor.g);
	s.smoothness = lerp(s.smoothness, 0.97, wetness);
}
#else
#define ApplyWetness(a, b)
#endif

#if defined(_SIMPLE_WATER)
half _FillRatio;
#include "Assets/PlayWay Water/Shaders/Utility/NoiseLib.cginc"

half3 GetWaterNormals(float4 texcoords, float3 worldPos)
{
	float2 perlinWorldPos = worldPos.xz * 2.5;
	float perlin_x = Perlin3D(float3(perlinWorldPos.x, _Time.y, perlinWorldPos.y));
	float perlin_y = Perlin3D(float3(perlinWorldPos.x + 131.171, _Time.y, perlinWorldPos.y));

	texcoords.xy += float2(perlin_x, perlin_y) * _PerlinIntensity;

	half2 uv1 = texcoords.xy + _Time.xx * half2(10, 10);
	half2 uv2 = texcoords.xy * 1.5 + _Time.xx * half2(-8.1, -11.1);

	return UnpackScaleNormal(tex2D(_BumpMap, uv1), _BumpScale) + UnpackScaleNormal(tex2D(_BumpMap, uv2), _BumpScale);
}
#endif

#endif