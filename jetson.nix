# The Jetson Orin extras (the advanced part, safe to ignore if you are just starting!)
# Kept out of flake.nix to keep that one easy to follow.
# flake.nix imports this file (aarch64-linux only) and exposes what it returns.
{
  nixpkgs,
  system,
  nix-ros-overlay,
  jetpack-nixos,
  wsPackages,
  my_awesome_interfaces,
  my_awesome_package,
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = true; # CUDA is unfree
      cudaCapabilities = [ "8.7" ]; # Jetson Orin, keep in sync with CMAKE_CUDA_ARCHITECTURES in my_awesome_cuda
    };
    overlays = [
      nix-ros-overlay.overlays.default
      jetpack-nixos.overlays.default
      (final: _: { cudaPackages = final.cudaPackages_12_6; }) # JetPack 6 ships CUDA 12.6
    ];
  };

  rosPkgs = pkgs.rosPackages.jazzy;

  # A CUDA talker for the Jetson, jetpack-nixos + cudaCapabilities 8.7 select the Jetson CUDA 12.6 builds
  # backendStdenv: a gcc that nvcc accepts, but linked to the same libstdc++ as ROS
  my_awesome_cuda = (rosPkgs.buildRosPackage.override { stdenv = pkgs.cudaPackages.backendStdenv; }) {
    pname = "my_awesome_cuda";
    version = "1.0.0";
    src = ./src/my_awesome_cuda;
    buildType = "ament_cmake";
    nativeBuildInputs = [
      rosPkgs.ament-cmake
      pkgs.cudaPackages.cuda_nvcc
    ];
    buildInputs = [
      pkgs.cudaPackages.cuda_cudart
      pkgs.cudaPackages.cccl
    ];
    propagatedBuildInputs = [
      rosPkgs.rclcpp
      rosPkgs.launch
      rosPkgs.launch-ros
      my_awesome_interfaces
      my_awesome_package
    ];
  };

  # Same workspace as in flake.nix, plus the CUDA talker
  # wsPackages are built with the flake.nix pkgs, fine as long as none of them depend on CUDA
  rosWorkspaceJetson = rosPkgs.buildEnv {
    name = "ros2-workspace-jetson";
    paths = wsPackages ++ [ my_awesome_cuda ];
  };

  # Same as ros2-bundle in flake.nix, but it launches the CUDA talker and uses JetPack's libcuda
  ros2-bundle-jetson = pkgs.writeShellApplication {
    name = "ros2-bundle-jetson";
    derivationArgs.pname = "ros2-bundle-jetson"; # nix bundle names its output "${pname}-arx"
    runtimeInputs = [ rosWorkspaceJetson ]; # puts `ros2` on the PATH
    runtimeEnv.RMW_IMPLEMENTATION = "rmw_zenoh_cpp";
    text = ''
      export ROS_DOMAIN_ID=''${ROS_DOMAIN_ID:-42}
      # libcuda.so must match the robot's kernel, so we use the one from JetPack
      export LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu/nvidia''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

      echo "Launching Zenoh Router Daemon..."
      ros2 run rmw_zenoh_cpp rmw_zenohd &
      ROUTER_PID=$!
      trap 'echo "Stopping Zenoh Router..."; kill "$ROUTER_PID" 2>/dev/null || true' EXIT

      ros2 launch my_awesome_cuda jetson.launch.py
    '';
  };
in
{
  ros2-workspace-jetson = rosWorkspaceJetson;
  inherit ros2-bundle-jetson;
}
