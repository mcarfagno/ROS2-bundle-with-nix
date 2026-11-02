#pragma once

#include <string>

// Adds [0..n) + [0..n) on the GPU and returns the sum of the result, or -1 on error.
long vector_add(int n);

std::string device_name();
