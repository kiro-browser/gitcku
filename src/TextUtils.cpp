#include "TextUtils.hpp"

#include <algorithm>
#include <cctype>
#include <sstream>

std::vector<std::string> splitLines(const std::string &text) {
    std::vector<std::string> lines;
    std::stringstream stream(text);
    std::string line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(line);
    }
    return lines;
}

std::string trim(const std::string &value) {
    size_t first = 0;
    while (first < value.size() && std::isspace(static_cast<unsigned char>(value[first]))) first++;
    size_t last = value.size();
    while (last > first && std::isspace(static_cast<unsigned char>(value[last - 1]))) last--;
    return value.substr(first, last - first);
}

std::string shorten(const std::string &value, int width) {
    if (width <= 0) return "";
    if (static_cast<int>(value.size()) <= width) return value;
    if (width <= 1) return value.substr(0, width);
    return value.substr(0, width - 1) + "~";
}

bool containsCaseInsensitive(const std::string &haystack, const std::string &needle) {
    if (needle.empty()) return true;
    auto lower = [](std::string text) {
        std::transform(text.begin(), text.end(), text.begin(), [](unsigned char ch) {
            return static_cast<char>(std::tolower(ch));
        });
        return text;
    };
    return lower(haystack).find(lower(needle)) != std::string::npos;
}
