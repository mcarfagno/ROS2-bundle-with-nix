{
  description = "ROS 2 Local Bundle and DevShell Tutorial";

  inputs = {
    nixpkgs.follows = "nix-ros-overlay/nixpkgs"; # IMPORTANT!!!
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
  };

  outputs = { self, nixpkgs, nix-ros-overlay }:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        # release version of your ros project
        releaseVersion = "1.0.1";

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-ros-overlay.overlays.default ];
        };

        # These are recipes that tell Nix how to build the ros packages in the workspace:
        # - Nix replaces colcon build
        # - If you are unsure how to write these look here:
        #  - https://github.com/lopsided98/nix-ros-overlay/tree/master/distros/jazzy
        #  - https://github.com/wentasah/ros2nix/
        my_awesome_interfaces = pkgs.rosPackages.jazzy.buildRosPackage {
          pname = "my_awesome_interfaces";
          version = "1.0.0"; # keep it synced with package.xml !
          src = ./src/my_awesome_interfaces;
          buildType = "ament_cmake";
          propagatedBuildInputs = [ pkgs.rosPackages.jazzy.rosidl-default-runtime ];
          nativeBuildInputs = [
            pkgs.rosPackages.jazzy.ament-cmake
            pkgs.rosPackages.jazzy.rosidl-default-generators
          ];
        };

        my_awesome_package = pkgs.rosPackages.jazzy.buildRosPackage {
          pname = "my_awesome_package";
          version = "1.0.0";
          src = ./src/my_awesome_package;
          buildType = "ament_cmake";
          nativeBuildInputs = [ pkgs.rosPackages.jazzy.ament-cmake ];
          propagatedBuildInputs = [
            pkgs.rosPackages.jazzy.rclcpp
            my_awesome_interfaces
          ];
        };

        my_awesome_bringup = pkgs.rosPackages.jazzy.buildRosPackage {
          pname = "my_awesome_bringup";
          version = "1.0.0";
          src = ./src/my_awesome_bringup;
          buildType = "ament_cmake";
          nativeBuildInputs = [ pkgs.rosPackages.jazzy.ament-cmake ];
          propagatedBuildInputs = [ my_awesome_package ];
        };

        # The hermetic ROS 2 environment with CLI tools and our custom packages
        rosWorkspace = pkgs.rosPackages.jazzy.buildEnv {
          name = "ros2-workspace";
          paths = [
            my_awesome_interfaces
            my_awesome_package
            my_awesome_bringup
            pkgs.rosPackages.jazzy.ros-core # bare minumum
            pkgs.rosPackages.jazzy.rmw-zenoh-cpp # ;-)
          ];
        };

      in {

        # --- PACKAGES (For nix bundle & nix build) ---
        packages = rec {
          # Setting 'default' means you can just run `nix bundle` with no arguments!
          default = ros2-bundle;

          # just the compiled workspce with the ros binaries, no autostart
          ros2-workspace = rosWorkspace;

          # the complied workspace wrapped with launch script
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

              # start zenoh router in background
              echo "Launching Zenoh Router Daemon..."
              ${rosWorkspace}/bin/ros2 run rmw_zenoh_cpp rmw_zenohd &
              ROUTER_PID=$!
              trap 'echo "Stopping Zenoh Router..."; kill $ROUTER_PID' EXIT

              # execute entry point as main shell process
              exec ${rosWorkspace}/bin/ros2 launch my_awesome_bringup my_bringup.launch.py
              EOF
              chmod +x $out/bin/ros2-bundle
            '';
            meta = {
              mainProgram = "ros2-bundle"; # here we point to the script we created above.
            };
          };
        };

        # --- APPS (For nix run) ---
        apps = {
          run-ros2-bundle = {
            type = "app";
            program = "${self.packages.${system}.ros2-bundle}/bin/ros2-bundle";
          };
        };

        # --- DEV SHELL (For nix develop) ---
        devShells.default = pkgs.mkShell {
          name = "ros2-jazzy-dev";

          # What is available in the shell 
          packages = [
            # generic dependecies from nixpkgs
            pkgs.colcon
            # ... other non-ROS packages
            (with pkgs.rosPackages.jazzy; buildEnv {
              paths = [
                ros-base # or desktop, but check NixGL for GUI tools
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
          # set any ENV you need
          shellHook = ''
            export RMW_IMPLEMENTATION=rmw_zenoh_cpp
            echo "🚀 Welcome to the ROS 2 Jazzy Sandbox!"
            echo "You can now run 'colcon build' or 'ros2 pkg create' natively."
          '';
        };
      });
      nixConfig = {
        extra-substituters = [ "https://ros.cachix.org" ];
        extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
      };
}
