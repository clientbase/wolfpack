Shader "Hidden/Blit"
{
    Properties
    {
        _MainTex("Main Texture", 2D) = "white" {}
		_Desaturation("Desaturation", Float) = 0
    }

    CGINCLUDE

        #include "UnityCG.cginc"

		struct AttributesDefault
		{
			float4 vertex : POSITION;
			float4 texcoord : TEXCOORD0;
		};

        struct Varyings
        {
            float2 uv : TEXCOORD0;
            float4 vertex : SV_POSITION;
        };

		sampler2D _MainTex;
		half4 _MainTex_CustomST;
		half _Desaturation;

        Varyings VertBlit(AttributesDefault v)
        {
            Varyings o;
            o.vertex = UnityObjectToClipPos(v.vertex);
            o.uv = UnityStereoScreenSpaceUVAdjust(v.texcoord, _MainTex_CustomST);
            return o;
        }

        half4 FragBlit(Varyings i) : SV_Target
        {
            half4 col = tex2D(_MainTex, i.uv);
            return col;
        }

		half4 FragBlitDesaturated(Varyings i) : SV_Target
        {
            half4 col = tex2D(_MainTex, i.uv);
            return half4(lerp(col.rgb, dot(col.rgb, half3(0.3, 0.59, 0.11)), _Desaturation), col.a);
        }

    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM

                #pragma vertex VertBlit
                #pragma fragment FragBlit

            ENDCG
        }

		Pass
        {
            CGPROGRAM

                #pragma vertex VertBlit
                #pragma fragment FragBlitDesaturated

            ENDCG
        }
    }
}
