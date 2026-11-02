{
  description = "My ROS 2 project with Nix";

  inputs = {
    nixpkgs.follows = "nix-ros-overlay/nixpkgs"; # IMPORTANT!!!
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";

    # NVIDIA Jetson goodies (CUDA, L4T libs, ...), only used for the aarch64 Jetson bundle
    jetpack-nixos.url = "github:anduril/jetpack-nixos/master";
    jetpack-nixos.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-ros-overlay,
      jetpack-nixos,
    }:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Only used by the Jetson CUDA package. We don't set cudaSupport = true,
          # so the ROS packages are still pulled from cachix!
          config = {
            allowUnfree = true; # CUDA is unfree
            cudaCapabilities = [ "8.7" ]; # Jetson Orin
          };
          overlays = [
            nix-ros-overlay.overlays.default
            jetpack-nixos.overlays.default
            (final: _: { cudaPackages = final.cudaPackages_12_6; }) # JetPack 6 ships CUDA 12.6
          ];
        };

        # This is the ros release this project is based upon.
        rosPkgs = pkgs.rosPackages.jazzy;

        # These are recipes that tell Nix how to build the ros packages in the workspace:
        # - Nix replaces colcon build
        # - If you are unsure how to write these look here:
        #  - https://github.com/lopsided98/nix-ros-overlay/tree/master/distros/jazzy
        #  - https://github.com/wentasah/ros2nix/
        my_awesome_interfaces = rosPkgs.buildRosPackage {
          pname = "my_awesome_interfaces";
          version = "1.0.0";
          src = ./src/my_awesome_interfaces;
          buildType = "ament_cmake";
          propagatedBuildInputs = [ rosPkgs.rosidl-default-runtime ];
          nativeBuildInputs = [
            rosPkgs.ament-cmake
            rosPkgs.rosidl-default-generators
            pkgs.python3Packages.numpy
          ];
          # needed to fix build under QEMU aarch64 emulation
          cmakeFlags = [
            "-DPython3_NumPy_INCLUDE_DIR=${pkgs.python3Packages.numpy.coreIncludeDir}"
          ];
        };

        my_awesome_package = rosPkgs.buildRosPackage {
          pname = "my_awesome_package";
          version = "1.0.0";
          src = ./src/my_awesome_package;
          buildType = "ament_cmake";
          nativeBuildInputs = [ rosPkgs.ament-cmake ];
          propagatedBuildInputs = [
            rosPkgs.rclcpp
            my_awesome_interfaces
          ];
        };

        my_awesome_bringup = rosPkgs.buildRosPackage {
          pname = "my_awesome_bringup";
          version = "1.0.0";
          src = ./src/my_awesome_bringup;
          buildType = "ament_cmake";
          nativeBuildInputs = [ rosPkgs.ament-cmake ];
          propagatedBuildInputs = [
            rosPkgs.launch
            rosPkgs.launch-ros
            my_awesome_package
          ];
        };

        # A CUDA talker for the Jetson, the CUDA bits come from the jetpack-nixos overlay
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

        # Everything that goes in the hermetic ROS 2 environment
        wsPackages = [
          # ros2 packages built from ws
          my_awesome_interfaces
          my_awesome_package
          my_awesome_bringup

          # ros2 packages from the overlay
          rosPkgs.ros-core # bare minimum ros libraries
          rosPkgs.rmw-zenoh-cpp # ;-)

          # runtime-only system libraries (e.g. for launchfiles)
          # pkgs.can-utils # don't forget the pkgs. part if it's not from the overlay!
        ];

        # The hermetic ROS 2 environments with compiled workspace
        rosWorkspace = rosPkgs.buildEnv {
          name = "ros2-workspace";
          paths = wsPackages;
        };
        rosWorkspaceJetson = rosPkgs.buildEnv {
          name = "ros2-workspace-jetson";
          paths = wsPackages ++ [ my_awesome_cuda ];
        };

        # defines a start script for the whole ros project
        mkBundle =
          name: workspace: launchFile:
          pkgs.writeShellScriptBin name ''
            export ROS_DOMAIN_ID=''${ROS_DOMAIN_ID:-42}
            export RMW_IMPLEMENTATION=rmw_zenoh_cpp
            # Jetson only: libcuda.so must match the robot's kernel, so we use the one from JetPack
            export LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu/nvidia''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

            echo "Launching Zenoh Router Daemon..."
            ${workspace}/bin/ros2 run rmw_zenoh_cpp rmw_zenohd &
            ROUTER_PID=$!
            trap 'echo "Stopping Zenoh Router..."; kill $ROUTER_PID' EXIT

            # no exec here, or the trap above would never fire!
            ${workspace}/bin/ros2 launch ${launchFile}
          '';

        ros2-bundle = mkBundle "ros2-bundle" rosWorkspace "my_awesome_bringup my_bringup.launch.py";
      in
      {
        # NIX PACKAGES (For nix bundle, nix build & nix run)
        packages = {
          default = ros2-bundle;

          # Workspace & bundle (runs on your laptop or ARM64 via --system)
          ros2-workspace = rosWorkspace;
          inherit ros2-bundle;
        }
        // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
          # Jetson Orin workspace & bundle (aarch64 only)
          ros2-workspace-jetson = rosWorkspaceJetson;
          ros2-bundle-jetson =
            mkBundle "ros2-bundle-jetson" rosWorkspaceJetson
              "my_awesome_cuda jetson.launch.py";
        };

        # --- DEV SHELL (For nix develop) ---
        # Note: We use `pkgs` (native) here, as shell tools run on your host!
        devShells.default = pkgs.mkShell {
          name = "ros2-jazzy-dev";

          packages = [
            pkgs.colcon
            pkgs.python3Packages.argcomplete
            # ... other non-ROS packages
            (rosPkgs.buildEnv {
              paths = with rosPkgs; [
                ros-base # desktop, but use nixGl for GUI tools!
                python-cmake-module
                ament-cmake-core
                rosidl-default-generators
                ament-lint-auto
                ament-lint-common
                # ... other ROS packages from the overlay
                rmw-zenoh-cpp
              ];
            })
          ];
          # This script runs the moment you enter the shell
          shellHook = ''
            export RMW_IMPLEMENTATION=rmw_zenoh_cpp
            eval "$(register-python-argcomplete ros2)"
            eval "$(register-python-argcomplete colcon)"
            echo "🚀 Welcome to the ROS 2 Jazzy Sandbox!"
            echo "You can now run 'colcon build' or 'ros2 pkg create' natively."
          '';
        };

        formatter = pkgs.nixfmt;
      }
    );

  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };
}
