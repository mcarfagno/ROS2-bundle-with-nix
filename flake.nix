# New to Nix + ROS 2? Read https://sgvd.ai/post/2026-03-25-ros2-with-nix/ first!
# The dev shell part (inputs, pkgs, devShells, nixConfig) is the flake from that post plus the jetpack-nixos input,
# the rest is what I added to build the workspace as a package and bundle it.
{
  description = "My ROS 2 project with Nix";

  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    # IMPORTANT!!! use the nixpkgs the overlay was built against, or the cachix hashes won't match and you compile the world
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";

    # NVIDIA Jetson goodies (CUDA, L4T libs, ...), only used for the aarch64 Jetson bundle (see jetson.nix)
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
    # reuses the overlay's flake-utils to set things up for your specific system
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-ros-overlay.overlays.default ];
        };

        # This is the ros release this project is based upon (humble, jazzy, kilted, rolling).
        rosPkgs = pkgs.rosPackages.jazzy;
      in
      {
        # --- DEV SHELL (For nix develop) ---
        devShells.default = pkgs.mkShell {
          name = "ros2-jazzy-dev";

          packages = [
            pkgs.colcon
            pkgs.python3Packages.argcomplete
            # ... other non-ROS packages
            (rosPkgs.buildEnv {
              paths = with rosPkgs; [
                ros-base # headless! for GUI tools (rviz2) add desktop and use nixGL
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
            export ROS_DOMAIN_ID=''${ROS_DOMAIN_ID:-42}
            eval "$(register-python-argcomplete ros2)"
            eval "$(register-python-argcomplete colcon)"
            echo "🚀 Welcome to the ROS 2 Jazzy Sandbox!"
            echo "You can now run 'colcon build' or 'ros2 pkg create' natively."
          '';
        };

        # --- NIX PACKAGES (For nix build, nix run & nix bundle) ---
        # Here is where we go beyond the dev shell: build and ship the workspace with Nix!
        packages =
          let
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

            # Everything that goes in the isolated ROS 2 environment
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

            # The isolated ROS 2 environment with compiled workspace
            rosWorkspace = rosPkgs.buildEnv {
              name = "ros2-workspace";
              paths = wsPackages;
            };

            # defines a start script for the whole ros project
            ros2-bundle = pkgs.writeShellApplication {
              name = "ros2-bundle";
              derivationArgs.pname = "ros2-bundle"; # nix bundle names its output "${pname}-arx"
              runtimeInputs = [ rosWorkspace ]; # puts `ros2` on the PATH
              runtimeEnv.RMW_IMPLEMENTATION = "rmw_zenoh_cpp";
              text = ''
                export ROS_DOMAIN_ID=''${ROS_DOMAIN_ID:-42}

                echo "Launching Zenoh Router Daemon..."
                ros2 run rmw_zenoh_cpp rmw_zenohd &
                ROUTER_PID=$!
                trap 'echo "Stopping Zenoh Router..."; kill "$ROUTER_PID" 2>/dev/null || true' EXIT

                ros2 launch my_awesome_bringup my_bringup.launch.py
              '';
            };
          in
          {
            default = ros2-bundle;

            # Workspace & bundle (runs on your laptop or ARM64 via --system)
            ros2-workspace = rosWorkspace;
            inherit ros2-bundle;
          }
          # Jetson Orin workspace & bundle (aarch64 only), all the CUDA stuff lives in jetson.nix
          // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") (
            import ./jetson.nix {
              inherit
                nixpkgs
                system
                nix-ros-overlay
                jetpack-nixos
                wsPackages
                my_awesome_interfaces
                my_awesome_package
                ;
            }
          );

        formatter = pkgs.nixfmt;
      }
    );

  # the cachix cache with prebuilt ROS packages, nix will ask you to accept it the first time
  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };
}
