#ifndef TERRAIN_SPLATMAP_COMMON_CGINC_INCLUDED
#define TERRAIN_SPLATMAP_COMMON_CGINC_INCLUDED

#define COMPENSATE_EARTH_CURVATURE_PER_VERTEX 1
#include "PlayWay Water/Shaders/Includes/EarthCurvature.cginc"

struct Input
{
	float2 uv_Splat0 : TEXCOORD0;
	float2 uv_Splat1 : TEXCOORD1;
	float2 uv_Splat2 : TEXCOORD2;
	float2 uv_Splat3 : TEXCOORD3;
	float2 tc_Control : TEXCOORD4;	// Not prefixing '_Contorl' with 'uv' allows a tighter packing of interpolators, which is necessary to support directional lightmap.
	float elevation : TEXCOORD5;
};

sampler2D _Control;
float4 _Control_ST;
float4 _TerrainOffset;
float _NormalScale;
half _GlobalMapAlbedoMix;
half _GlobalMapHeightmapMix;
sampler2D _Splat0,_Splat1,_Splat2,_Splat3,_Splat4;

#ifdef _TERRAIN_NORMAL_MAP
	sampler2D _Normal0, _Normal1, _Normal2, _Normal3, _Normal4;
#endif

#ifdef HEIGHTMAP
	sampler2D _Heightmap;
	half4 _Heightmap_TexelSize;
#endif

	inline half2 approxTanh(half2 x)
	{
		return x / sqrt(1.0 + x * x);
	}

void SplatmapVert(inout appdata_full v, out Input data)
{
	UNITY_INITIALIZE_OUTPUT(Input, data);
	data.tc_Control = TRANSFORM_TEX(v.texcoord, _Control);	// Need to manually transform uv here, as we choose not to use 'uv' prefix for this texcoord.
	v.vertex += _TerrainOffset;
#if defined(HEIGHTMAP)
	v.texcoord.xy = (v.texcoord.xy * (_Heightmap_TexelSize.zw - 1) + 0.5) / _Heightmap_TexelSize.zw;

	float minElevation = lerp(0.0, 600 / 3200.0f, _GlobalMapHeightmapMix);
	float elevation = max(minElevation, tex2Dlod(_Heightmap, v.texcoord));
	v.vertex.y += elevation;
	data.elevation = elevation * 3200 - 600;

	/*v.normal.x = max(600 / 3200, elevation) - max(600 / 3200, tex2Dlod(_Heightmap, v.texcoord + float4(_Heightmap_TexelSize.x, 0, 0, 0)));
	v.normal.z = max(600 / 3200, elevation) - max(600 / 3200, tex2Dlod(_Heightmap, v.texcoord + float4(0, _Heightmap_TexelSize.y, 0, 0)));
	v.normal.xz = v.normal.xz  * 15000000.0 * _NormalScale;
	v.normal.y = 0.08;
	v.normal = normalize(v.normal);*/

#else
	data.elevation = v.vertex.y - 600.0;
#endif
	v.vertex.y = CompensateForEarthCurvature(v.vertex + float4(unity_ObjectToWorld[0].w, 0.0, unity_ObjectToWorld[2].w, 0.0)).y;

#ifdef _TERRAIN_NORMAL_MAP
	v.tangent.xyz = cross(v.normal, float3(0,0,1));
	v.tangent.w = -1;
#endif
}

#ifdef TERRAIN_STANDARD_SHADER
void SplatmapMix(Input IN, half4 defaultAlpha, out half4 splat_control, out half weight, out fixed4 mixedDiffuse, inout fixed3 mixedNormal)
#else
void SplatmapMix(Input IN, out half4 splat_control, out half weight, out fixed4 mixedDiffuse, inout fixed3 mixedNormal)
#endif
{
	splat_control = tex2D(_Control, IN.tc_Control);

#if !defined(DONT_USE_ELEVATION_DATA)
	half beach = saturate((3.5 - IN.elevation) * 0.08);
	splat_control.g += beach;
	splat_control.r = max(0.0, splat_control.r - beach);
#endif

	weight = dot(splat_control, half4(1,1,1,1));

	#if !defined(SHADER_API_MOBILE) && defined(TERRAIN_SPLAT_ADDPASS)
		clip(weight == 0.0f ? -1 : 1);
	#endif

	// Normalize weights before lighting and restore weights in final modifier functions so that the overal
	// lighting result can be correctly weighted.
	//splat_control /= (weight + 1e-3f);
	half fifthTexIntensity = 1.0 - weight;

	mixedDiffuse = 0.0f;
	#ifdef TERRAIN_STANDARD_SHADER
		mixedDiffuse += splat_control.r * tex2D(_Splat0, IN.uv_Splat0)/* * half4(1.0, 1.0, 1.0, defaultAlpha.r)*/;
		mixedDiffuse += splat_control.g * tex2D(_Splat1, IN.uv_Splat1)/* * half4(1.0, 1.0, 1.0, defaultAlpha.g)*/;
		mixedDiffuse += splat_control.b * tex2D(_Splat2, IN.uv_Splat2)/* * half4(1.0, 1.0, 1.0, defaultAlpha.b)*/;
		mixedDiffuse += splat_control.a * tex2D(_Splat3, IN.uv_Splat3)/* * half4(1.0, 1.0, 1.0, defaultAlpha.a)*/;
		mixedDiffuse += fifthTexIntensity * tex2D(_Splat4, IN.uv_Splat3 * 0.0165);
	#else
		mixedDiffuse += splat_control.r * tex2D(_Splat0, IN.uv_Splat0);
		mixedDiffuse += splat_control.g * tex2D(_Splat1, IN.uv_Splat1);
		mixedDiffuse += splat_control.b * tex2D(_Splat2, IN.uv_Splat2);
		mixedDiffuse += splat_control.a * tex2D(_Splat3, IN.uv_Splat3);
		mixedDiffuse += fifthTexIntensity * tex2D(_Splat4, IN.uv_Splat3 * 0.0165);
	#endif

	#ifdef _TERRAIN_NORMAL_MAP
		fixed4 nrm = 0.0f;
		nrm += splat_control.r * tex2D(_Normal0, IN.uv_Splat0);
		nrm += splat_control.g * tex2D(_Normal1, IN.uv_Splat1);
		nrm += splat_control.b * tex2D(_Normal2, IN.uv_Splat2);
		nrm += splat_control.a * tex2D(_Normal3, IN.uv_Splat3);
		nrm += fifthTexIntensity * tex2D(_Normal4, IN.uv_Splat3 * 0.0165);
		mixedNormal = UnpackNormal(nrm);
	#endif
}

#ifndef TERRAIN_SURFACE_OUTPUT
	#define TERRAIN_SURFACE_OUTPUT SurfaceOutput
#endif

void SplatmapFinalColor(Input IN, TERRAIN_SURFACE_OUTPUT o, inout fixed4 color)
{
	color *= o.Alpha;
}

void SplatmapFinalPrepass(Input IN, TERRAIN_SURFACE_OUTPUT o, inout fixed4 normalSpec)
{
	normalSpec *= o.Alpha;
}

void SplatmapFinalGBuffer(Input IN, TERRAIN_SURFACE_OUTPUT o, inout half4 diffuse, inout half4 specSmoothness, inout half4 normal, inout half4 emission)
{
	diffuse.rgb *= o.Alpha;
	specSmoothness *= o.Alpha;
	normal.rgb *= o.Alpha;
	emission *= o.Alpha;
}

#endif // TERRAIN_SPLATMAP_COMMON_CGINC_INCLUDED
