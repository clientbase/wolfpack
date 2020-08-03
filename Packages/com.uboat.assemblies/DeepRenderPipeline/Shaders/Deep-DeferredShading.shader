Shader "Hidden/Deep-DeferredShading" {
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
		Ref[_CameraIndex]
		Comp Equal
	}

	ZWrite Off
	ZTest [_CompareFunc]
	Cull [_CullMode]
	Blend One One, One Zero

HLSLPROGRAM
#pragma target 4.5
#pragma vertex vert
#pragma fragment frag
#pragma multi_compile_lightpass
#define UNITY_HDR_ON 1
#pragma multi_compile _ HIGH_QUALITY_PCF
#pragma multi_compile _ WATER_BUFFERS_ENABLED

#pragma exclude_renderers nomrt

#include "UnityCG.cginc"
#include "UnityDeferredLibrary.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardBRDF.cginc"

#include "LightingTemplate.hlsl"

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

CGPROGRAM
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
#ifdef UNITY_SINGLE_PASS_STEREO
	o.texcoord = TransformStereoScreenSpaceTex(o.texcoord, 1.0f);
#endif
	return o;
}

fixed4 frag (v2f i) : SV_Target
{
	return -log2(tex2D(_LightBuffer, i.texcoord));
}
ENDCG 
}

}
Fallback Off
}
