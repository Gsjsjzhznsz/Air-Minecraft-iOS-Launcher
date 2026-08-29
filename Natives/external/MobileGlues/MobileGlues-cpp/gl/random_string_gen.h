// MobileGlues - gl/random_string_gen.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#include <string>
#include <random>
#include <vector>
#include <algorithm>
#include <stdexcept>
#include <unordered_set>
#include <string>
#include <format>

struct RandomStringOptions {
    size_t minLength = 8;
    size_t maxLength = 16;
    bool includeLowercase = true;
    bool includeUppercase = true;
    bool includeDigits = true;
    bool includeSpecial = false;
    std::string customChars = "";
    bool allowRepeat = true;
    bool mustIncludeEachType = false;
};

std::string GenerateRandomString(const RandomStringOptions& opts);