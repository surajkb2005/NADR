import React, { useRef, useMemo, useState } from "react";
import { Canvas, useFrame, useLoader } from "@react-three/fiber";
import { OrbitControls, Stars, Sphere, Trail, Float } from "@react-three/drei";
import * as THREE from "three";
import { TextureLoader } from 'three';

// --- CONFIGURATION ---
const EARTH_RADIUS = 2;
const IONOSPHERE_RADIUS = 2.3; 
const MAGNETOSPHERE_RADIUS = 3.5; 
const SUN_POSITION = [-25, 0, 0]; 
const SUN_RADIUS = 8;

/**
 * ☀️ THE SUN (Textured)
 */
const Sun = () => {
  // Ensure 'sun_map.jpg' exists in public/textures/
  const sunTexture = useLoader(TextureLoader, '/textures/sun_map.jpg');

  return (
    <group position={SUN_POSITION}>
      <Sphere args={[SUN_RADIUS, 64, 64]}>
        <meshBasicMaterial map={sunTexture} color="#ffffff" />
      </Sphere>
      <Sphere args={[SUN_RADIUS * 1.05, 64, 64]}>
        <meshBasicMaterial color="#FF8C00" transparent opacity={0.4} />
      </Sphere>
      <Sphere args={[SUN_RADIUS * 1.2, 64, 64]}>
        <meshBasicMaterial color="#FF4500" transparent opacity={0.1} />
      </Sphere>
      <pointLight intensity={3} distance={100} decay={0} color="#FF8C00" />
    </group>
  );
};

/**
 * 🌍 EARTH
 */
const Earth = () => {
  const [colorMap, bumpMap, specularMap] = useLoader(TextureLoader, [
    '/textures/earth_daymap.jpg',
    '/textures/earth_bump.jpg',
    '/textures/earth_specular.jpg'
  ]);

  return (
    <group>
      <Sphere args={[EARTH_RADIUS, 64, 64]}>
        <meshPhongMaterial
          map={colorMap}
          bumpMap={bumpMap}
          bumpScale={0.05}
          specularMap={specularMap}
          specular={new THREE.Color('grey')}
          shininess={5}
        />
      </Sphere>
      <Sphere args={[EARTH_RADIUS + 0.04, 64, 64]}>
        <meshPhongMaterial
          color="#4299E1"
          transparent
          opacity={0.1}
          side={THREE.BackSide}
          blending={THREE.AdditiveBlending}
        />
      </Sphere>
    </group>
  );
};

/**
 * 📡 IONOSPHERE (Updated: Much Lighter/Fainter)
 */
const Ionosphere = ({ intensity }) => {
  const ionoRef = useRef();

  useFrame((state) => {
    if (ionoRef.current) {
        const t = state.clock.getElapsedTime();
        // --- CHANGE: Drastically reduced opacity ---
        // Base opacity is now 0.02 (very faint). 
        // Even at max storm intensity, it only goes up slightly.
        const baseOpacity = 0.02 + (intensity * 0.01);
        
        // Pulse is also subtle
        ionoRef.current.material.opacity = baseOpacity + (Math.sin(t * 5) * 0.01);
        ionoRef.current.rotation.y -= 0.002;
    }
  });

  const ionoColor = "#00FFFF"; 

  return (
    <Sphere ref={ionoRef} args={[IONOSPHERE_RADIUS, 64, 64]}>
      <meshPhongMaterial
        color={ionoColor}
        emissive={ionoColor}
        emissiveIntensity={0.2} // Reduced glow intensity
        transparent
        opacity={0.05} // Very transparent default
        wireframe={true} 
        side={THREE.DoubleSide}
        depthWrite={false} // Prevents it from occluding the earth
      />
    </Sphere>
  );
};

/**
 * 🛡️ MAGNETOSPHERE SHIELD
 */
const Magnetosphere = ({ intensity }) => {
  const shieldRef = useRef();
  
  useFrame((state) => {
    if (shieldRef.current) {
        const t = state.clock.getElapsedTime();
        shieldRef.current.material.opacity = 0.05 + (Math.sin(t * 3) * 0.05 * (intensity / 5));
        shieldRef.current.rotation.z -= 0.002;
    }
  });

  const shieldColor = intensity > 5 ? "#FF4500" : "#4488FF";

  return (
    <Sphere ref={shieldRef} args={[MAGNETOSPHERE_RADIUS, 64, 64]}>
      <meshPhongMaterial
        color={shieldColor}
        emissive={shieldColor}
        emissiveIntensity={intensity > 5 ? 0.4 : 0.1}
        transparent
        opacity={0.1}
        side={THREE.DoubleSide}
        depthWrite={false}
      />
    </Sphere>
  );
};

/**
 * 🔥 SOLAR FLARES (Slow & Colliding)
 */
const SolarFlares = ({ count = 20, intensity }) => {
  const particles = useMemo(() => {
    return new Array(count).fill(0).map(() => ({
      x: SUN_POSITION[0] + SUN_RADIUS, 
      y: (Math.random() - 0.5) * 5, 
      z: (Math.random() - 0.5) * 5, 
      speed: 0.05 + Math.random() * 0.1, 
      scale: 0.3 + Math.random() * 0.4 
    }));
  }, [count]);

  const mesh = useRef();

  useFrame((state) => {
    const speedMultiplier = 1 + (intensity / 5); 
    
    mesh.current.children.forEach((p, i) => {
        const data = particles[i];
        p.position.x += data.speed * speedMultiplier;
        
        // Stop at outer shield
        if (p.position.x > -MAGNETOSPHERE_RADIUS + 0.5) { 
            p.position.x = SUN_POSITION[0] + SUN_RADIUS + Math.random();
            p.position.y = (Math.random() - 0.5) * 5;
            p.position.z = (Math.random() - 0.5) * 5;
        }
    });
  });

  const flareColor = "#FF6600"; 

  return (
    <group ref={mesh}>
      {particles.map((data, i) => (
        <mesh key={i} position={[data.x, data.y, data.z]} scale={data.scale}>
          <sphereGeometry args={[0.1, 8, 8]} />
          <meshBasicMaterial color={flareColor} transparent opacity={0.6} />
          <Trail width={1.5} length={6} color={flareColor} attenuation={(t) => t * t}>
             <mesh />
          </Trail>
        </mesh>
      ))}
    </group>
  );
};

/**
 * 🎮 MAIN SCENE
 */
const SolarStormGlobe = ({ kpIndex = 3 }) => {
  const [localKp, setLocalKp] = useState(kpIndex);
  const currentKp = kpIndex || localKp;

  return (
    <div style={{ width: "100%", height: "100%", position: "relative", background: "black" }}>
      
      <div style={{ position: "absolute", top: 20, left: 20, zIndex: 10, color: "white", pointerEvents: 'none' }}>
        <h2 style={{ margin: 0, fontSize: "1rem", fontWeight: "bold", letterSpacing: "1px", color: "#FDB813" }}>
          SOLAR ACTIVITY MONITOR
        </h2>
        <div style={{ marginTop: "5px", display: "flex", alignItems: "center", gap: "10px" }}>
            <span style={{ fontSize: "0.8rem", color: "#94A3B8" }}>STORM LEVEL:</span>
            <span style={{ 
                fontSize: "1.2rem", 
                fontWeight: "bold", 
                color: currentKp > 6 ? "#EF4444" : currentKp > 4 ? "#FBBF24" : "#4ADE80" 
            }}>
                Kp {currentKp}
            </span>
        </div>
      </div>

      <Canvas camera={{ position: [0, 2, 16], fov: 45 }} gl={{ antialias: true }}>
        <React.Suspense fallback={null}>
            <ambientLight intensity={0.05} /> 
            <Stars radius={200} depth={50} count={3000} factor={4} saturation={0} fade speed={0.5} />
            
            <Sun />
            <SolarFlares count={20} intensity={currentKp} />

            <Float speed={0.2} rotationIntensity={0.1} floatIntensity={0.1}>
                <group rotation={[0, THREE.MathUtils.degToRad(180), 0]}>
                    <Earth />
                </group>
                <Ionosphere intensity={currentKp} />
                <Magnetosphere intensity={currentKp} />
            </Float>
        </React.Suspense>

        <OrbitControls 
            enableZoom={true} 
            enablePan={true}
            minDistance={5} 
            maxDistance={60} 
        />
      </Canvas>
    </div>
  );
};

export default SolarStormGlobe;