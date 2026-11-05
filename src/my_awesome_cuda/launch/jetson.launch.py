from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='my_awesome_cuda',
            executable='cuda_talker',
            name='cuda_talker',
        ),
        Node(
            package='my_awesome_package',
            executable='listener',
            name='listener',
        ),
    ])
