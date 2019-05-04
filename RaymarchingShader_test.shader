// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Hidden/RaymarchSpheresShader"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
	}
	SubShader
	{
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			// Provided by our script
            uniform float4x4 _FrustumCornersES;
            uniform sampler2D _MainTex;
            uniform sampler2D _CameraDepthTexture;
            uniform float4 _MainTex_TexelSize;
            uniform float4x4 _CameraInvViewMatrix;
            uniform float4x4 _Points[20];
            uniform int _Points_size;
            uniform float3 _CameraWS;
            uniform float _Interpolator;
            uniform float4 _LightColor;
            uniform float4 _ShadowColor;
           
            // Input to vertex shader
            struct appdata
            {
                // Remember, the z value here contains the index of _FrustumCornersES to use
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };
            
            // Output of vertex shader / input to fragment shader
            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 ray : TEXCOORD1;
            };

            // Torus
            // t.x: diameter
            // t.y: thickness
            // Adapted from: http://iquilezles.org/www/articles/distfunctions/distfunctions.htm
            float sdTorus(float3 p, float2 t)
            {
                float2 q = float2(length(p.xz) - t.x, p.y);
                return length(q) - t.y;
            }
            
            float sdSphere( float3 p, float s )
            {
              return length(p)-s;
            }
            
            float sdSphere2( float3 p, float s )
            {
              return length(p-float3(3,0,0))-s;
            }
            float sdSphere3( float3 p, float s )
            {
              return length(p-float3(1.5,0,2))-s;
            }
            
            float smin( float a, float b, float k )
            {
                float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
                return lerp( b, a, h ) - k*h*(1.0-h);
            }           
            // This is the distance field function.  The distance field represents the closest distance to the surface
            // of any object we put in the scene.  If the given point (point p) is inside of an object, we return a
            // negative answer.
            float map(float3 p) {
                //return sdTorus(p, float2(1, 0.2));
                //return lerp(sdSphere(p, 1),sdTorus(p, float2(0.8, 0.2)),_Interpolator);
                //return lerp(sdSphere(p, 1),sdSphere2(p, 1),_Interpolator);
                //return smin(smin(sdSphere(p, 1),sdSphere2(p, 1),_Interpolator),sdSphere3(p, 1),_Interpolator);
                float4 q = mul(_Points[0], float4(p,1));
                float s = sdSphere(q.xyz, 1);
                float ret = s;
                for (int i=1; i < _Points_size; i ++)
                {
                    q = mul(_Points[i], float4(p,1));
                    s = sdSphere(q.xyz, 1);
                    ret = smin(ret,s,_Interpolator);
                }
                return ret;
            }
            
            float3 calcNormal(in float3 pos)
            {
                // epsilon - used to approximate dx when taking the derivative
                const float2 eps = float2(0.001, 0.0);
            
                // The idea here is to find the "gradient" of the distance field at pos
                // Remember, the distance field is not boolean - even if you are inside an object
                // the number is negative, so this calculation still works.
                // Essentially you are approximating the derivative of the distance field at this point.
                float3 nor = float3(
                    map(pos + eps.xyy).x - map(pos - eps.xyy).x,
                    map(pos + eps.yxy).x - map(pos - eps.yxy).x,
                    map(pos + eps.yyx).x - map(pos - eps.yyx).x);
                return normalize(nor);
            }
            // Raymarch along given ray
            // ro: ray origin
            // rd: ray direction
            fixed4 raymarch(float3 ro, float3 rd, float s) {
                fixed4 ret = fixed4(0,0,0,0);
            
                const int maxstep = 64;
                float t = 0; // current distance traveled along ray
                for (int i = 0; i < maxstep; ++i) {
                    float3 p = ro + rd * t; // World space position of sample
                    float d = map(p);       // Sample of distance field (see map())
            
                    // If the sample <= 0, we have hit something (see map()).
                    if (d < 0.001) {
                        // Simply return a gray color if we have hit an object
                        // We will deal with lighting later.
                        //ret = fixed4(0.5, 0.5, 0.5, 1);
                        float3 n = calcNormal(p);
                        float r = dot(_WorldSpaceLightPos0.xyz, n).r;
//                        ret =  fixed4(dot(_WorldSpaceLightPos0.xyz, n).rrr, 1);
                        ret = r*_LightColor + (1-r)*_ShadowColor;
                        break;
                    }
                    if (t >= s) 
                    {
                        ret = fixed4(0, 0, 0, 0);
                        break;
                    }
                    // If the sample > 0, we haven't hit anything yet so we should march forward
                    // We step forward by distance d, because d is the minimum distance possible to intersect
                    // an object (see map()).
                    t += d;
                }
            
                return ret;
            }
            

            
            v2f vert (appdata v)
            {
                v2f o;
                
                // Index passed via custom blit function in RaymarchGeneric.cs
                half index = v.vertex.z;
                v.vertex.z = 0.1;
                
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv.xy;
                
                #if UNITY_UV_STARTS_AT_TOP
                if (_MainTex_TexelSize.y < 0)
                    o.uv.y = 1 - o.uv.y;
                #endif
            
                // Get the eyespace view ray (normalized)
                o.ray = _FrustumCornersES[(int)index].xyz;
            
                // Transform the ray from eyespace to worldspace
                // Note: _CameraInvViewMatrix was provided by the script
                o.ray = mul(_CameraInvViewMatrix, o.ray);
                return o;
            }
            fixed4 frag (v2f i) : SV_Target
            {
                // ray direction
                float3 rd = normalize(i.ray.xyz);
                // ray origin (camera position)
                float3 ro = _CameraWS;
                float2 duv = i.uv;
                #if UNITY_UV_STARTS_AT_TOP
                if (_MainTex_TexelSize.y < 0)
                    duv.y = 1 - duv.y;
                #endif
                float depth = LinearEyeDepth(tex2D(_CameraDepthTexture, duv).r);
                depth *= length(i.ray.xyz);

                fixed3 col = tex2D(_MainTex,i.uv); // Color of the scene before this shader was run
                fixed4 add = raymarch(ro, rd,depth);
            
                // Returns final color using alpha blending
                return fixed4(col*(1.0 - add.w) + add.xyz * add.w,1.0);
            }
			ENDCG
		}
	}
}
