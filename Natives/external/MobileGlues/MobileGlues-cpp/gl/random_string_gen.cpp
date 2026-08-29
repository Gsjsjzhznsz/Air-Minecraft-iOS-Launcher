// MobileGlues - gl/random_string_gen.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#include "random_string_gen.h"

void InitRandom() {
    static bool inited = false;
    if (!inited) {
        std::srand(static_cast<unsigned>(std::time(nullptr)));
        inited = true;
    }
}

void ShuffleString(std::string& str) {
    for (int i = str.size() - 1; i > 0; --i) {
        int j = std::rand() % (i + 1);
        std::swap(str[i], str[j]);
    }
}

std::string GenerateRandomString(const RandomStringOptions& opts) {
    InitRandom();

    if (opts.minLength > opts.maxLength) throw std::invalid_argument("minLength cannot be greater than maxLength");

    std::string charset;
    std::vector<std::string> charTypes;

    if (opts.includeLowercase) {
        charset += "abcdefghijklmnopqrstuvwxyz";
        charTypes.push_back("abcdefghijklmnopqrstuvwxyz");
    }
    if (opts.includeUppercase) {
        charset += "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        charTypes.push_back("ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    }
    if (opts.includeDigits) {
        charset += "0123456789";
        charTypes.push_back("0123456789");
    }
    if (opts.includeSpecial) {
        charset += "!@#$%^&*()-_=+[]{}|;:',.<>?/";
        charTypes.push_back("!@#$%^&*()-_=+[]{}|;:',.<>?/");
    }
    if (!opts.customChars.empty()) {
        charset += opts.customChars;
        charTypes.push_back(opts.customChars);
    }

    if (charset.empty()) throw std::invalid_argument("No characters available to generate string");

    size_t length = opts.minLength + rand() % (opts.maxLength - opts.minLength + 1);
    std::string result;
    result.reserve(length);

    if (opts.mustIncludeEachType) {
        if (length < charTypes.size())
            throw std::invalid_argument("Length too short to include each required character type");

        for (const auto& type : charTypes) {
            char c = type[rand() % type.size()];
            result += c;
        }
    }

    while (result.size() < length) {
        char c = charset[rand() % charset.size()];
        if (!opts.allowRepeat && result.find(c) != std::string::npos) continue;
        result += c;
    }

    if (opts.mustIncludeEachType) {
        ShuffleString(result);
    }

    return result;
}