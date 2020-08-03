Shader "PlayWay Water/Deferred/GBuffer12Mix"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}

CGINCLUDE
	#include "UnityCG.cginc"

	struct appdata
	{
		float4 vertex : POSITION;
		float2 uv : TEXCOORD0;
	};

	struct v2f
	{
		float4 vertex : SV_POSITION;
		half4 uv : TEXCOORD0;
	};

	v2f vert(appdata v)
	{
		v2f o;
		o.vertex = v.vertex;
#if UNITY_UV_STARTS_AT_TOP
		o.vertex.y = -o.vertex.y;
#endif
		o.uv = half4(v.uv, 0, 0);
		return o;
	}

	sampler2D _WaterGBuffer1;
	sampler2D _WaterGBuffer2;
	sampler2D _OriginalGBuffer1;
	sampler2D _WaterlessDepthTexture;
	sampler2D _WaterDepthTexture;
	sampler2D _CameraDepthTexture;
	sampler2D _GlobalWaterLookupTex;
	half _DepthClipMultiplier;

	void frag(
		v2f i,
		//out half4 outDiffuse : SV_Target0,			// RT0: diffuse color (rgb), occlusion (a)
		out half4 outSpecSmoothness : SV_Target0,	// RT1: spec color (rgb), smoothness (a)
		out half4 outNormal : SV_Target1			// RT2: normal (rgb), --unused, very low precision-- (a) 
		//out half4 outEmission : SV_Target2			// RT3: emission (rgb), --unused-- (a)) : SV_Target
		)
	{
		half4 uv = UnityStereoTransformScreenSpaceTex(i.uv);
		half waterDepth = tex2Dlod(_CameraDepthTexture, uv);
		half waterlessDepth = tex2Dlod(_WaterlessDepthTexture, uv);

		half4 waterSpecSmoothness = tex2Dlod(_WaterGBuffer1, uv);
		half4 sceneSpecSmoothness = tex2Dlod(_OriginalGBuffer1, uv);
		outNormal = tex2Dlod(_WaterGBuffer2, uv);

		half blendEdgesFactor = saturate(5 * (LinearEyeDepth(waterlessDepth) - LinearEyeDepth(waterDepth)));
		outSpecSmoothness = lerp(sceneSpecSmoothness, waterSpecSmoothness, blendEdgesFactor);
		outNormal.a = blendEdgesFactor;
	}
ENDCG

	SubShader
	{
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			Stencil
			{
				Ref 8
				ReadMask 8
				WriteMask 8
				Comp Equal
			}

			Blend 0 One Zero
			Blend 1 SrcAlpha OneMinusSrcAlpha

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#pragma target 3.0
			
			ENDCG
		}
	}
}
