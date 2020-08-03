// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Hidden/SRP-BlitCopyDepth" {
	HLSLINCLUDE
        #pragma only_renderers d3d11 ps4 xboxone vulkan metal switch

        #include "CoreRP/ShaderLibrary/Common.hlsl"
		
		#include "UnityCG.cginc"

            UNITY_DECLARE_DEPTH_TEXTURE(_SourceDepthTex);
            uniform float4 _CopyRect;

            struct v2f {
                float4 vertex : SV_POSITION;
                float2 texcoord : TEXCOORD0;
            };

            v2f vert (uint vertexID : VERTEXID_SEMANTIC)
            {
                v2f o;
				o.vertex = GetFullScreenTriangleVertexPosition(vertexID);
				o.texcoord = GetFullScreenTriangleTexCoord(vertexID);
				o.texcoord = o.texcoord * _CopyRect.xy + _CopyRect.zw;
                return o;
            }

            float frag (v2f i) : SV_Depth
            {
                return SAMPLE_RAW_DEPTH_TEXTURE(_SourceDepthTex, i.texcoord);
            }
    ENDHLSL
	
    SubShader {
        Pass {
            ZTest Always Cull Off ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
			#pragma target 4.5

            ENDHLSL

        }
    }
    Fallback Off
}
