from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        Node(
            package='my_awesome_package',
            executable='talker',
            name='talker',
        ),
        Node(
            package='my_awesome_package',
            executable='listener',
            name='listener',
        ),
    ])
