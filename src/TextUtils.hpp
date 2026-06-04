#pragma once

#include <string>
#include <vector>

std::vector<std::string> splitLines(const std::string &text);
std::string trim(const std::string &value);
std::string shorten(const std::string &value, int width);
bool containsCaseInsensitive(const std::string &haystack, const std::string &needle);
