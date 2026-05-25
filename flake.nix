{
  description = "My ROS 2 project with Nix";

  inputs = {
    nixpkgs.follows = "nix-ros-overlay/nixpkgs"; # IMPORTANT!!!
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-ros-overlay,
    }:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        releaseVersion = "1.0.1";

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-ros-overlay.overlays.default ];
        };

        # Defines your ros workspace as a factory function
        makeRosWorkspace =
          pkgs:
          let
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
              propagatedBuildInputs = [ my_awesome_package ];
            };

            # The hermetic ROS 2 environment with compliled workspace
            rosWorkspace = rosPkgs.buildEnv {
              name = "ros2-workspace";
              paths = [
                # ros2 packes built from ws
                my_awesome_interfaces
                my_awesome_package
                my_awesome_bringup

                # ros2 packages from the overlay
                rosPkgs.ros-core # bare minumum ros libraries
                rosPkgs.rmw-zenoh-cpp # ;-)

                # runtime-only system libraries (e.g. for launchfiles)
                # pkgs.can-utils # don't forget the pkgs. part if it's not from the overlay!
              ];
            };

            # defines a start script for the whole ros project
            ros2-bundle = pkgs.stdenv.mkDerivation {
              pname = "ros2-bundle";
              version = releaseVersion;
              phases = [ "installPhase" ];
              installPhase = ''
                mkdir -p $out/bin
                cat << 'EOF' > $out/bin/ros2-bundle
                #!${pkgs.bash}/bin/bash
                export ROS_DOMAIN_ID=''${ROS_DOMAIN_ID:-42}
                export RMW_IMPLEMENTATION=rmw_zenoh_cpp

                echo "Launching Zenoh Router Daemon..."
                ${rosWorkspace}/bin/ros2 run rmw_zenoh_cpp rmw_zenohd &
                ROUTER_PID=$!
                trap 'echo "Stopping Zenoh Router..."; kill $ROUTER_PID' EXIT

                exec ${rosWorkspace}/bin/ros2 launch my_awesome_bringup my_bringup.launch.py
                EOF
                chmod +x $out/bin/ros2-bundle
              '';
              meta = {
                mainProgram = "ros2-bundle";
              };
            };
          in
          {
            inherit rosWorkspace ros2-bundle;
          };

        env = makeRosWorkspace pkgs;

      in
      {
        # NIX PACKAGES (For nix bundle & nix build)
        packages = {
          default = env.ros2-bundle;

          # Workspace & bundle (runs on your laptop or ARM64 via --system)
          ros2-workspace = env.rosWorkspace;
          ros2-bundle = env.ros2-bundle;
        };

        # --- APPS (For nix run) ---
        apps = {
          default = {
            type = "app";
            program = "${env.ros2-bundle}/bin/ros2-bundle";
          };
          run-ros2-bundle = {
            type = "app";
            program = "${env.ros2-bundle}/bin/ros2-bundle";
          };
        };

        # --- DEV SHELL (For nix develop) ---
        # Note: We use `pkgs` (native) here, as shell tools run on your host!
        devShells.default = pkgs.mkShell {
          name = "ros2-jazzy-dev";

          packages = [
            pkgs.colcon
            pkgs.python3Packages.argcomplete
            # ... other non-ROS packages
            (pkgs.rosPackages.jazzy.buildEnv {
              paths = with pkgs.rosPackages.jazzy; [
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

        formatter = pkgs.nixfmt-rfc-style;
      }
    );

  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };
}
