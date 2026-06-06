#pragma once

#include <cstddef>

namespace dietcode::domain::control {

constexpr size_t kMaxRequestBytes = 1024 * 1024;
constexpr size_t kMaxResponseBytes = 4 * 1024 * 1024;
constexpr int kMaxGrepResults = 500;
constexpr size_t kMaxFileTextBytes = 1024 * 1024;
constexpr size_t kMaxPatchBytesBeforeConfirmation = 10 * 1024;
constexpr size_t kMaxPatchBytes = 1024 * 1024;
constexpr int kMaxBatchPatchCount = 10;
constexpr size_t kMaxChunkPreviewLength = 180;
constexpr int kMaxSearchDepth = 10;
constexpr int kMaxSearchScanFiles = 10000;
constexpr size_t kMaxSearchFileBytes = 2 * 1024 * 1024;
constexpr int kMaxPlanSteps = 30;
constexpr int kMaxActiveCombos = 4;

} // namespace dietcode::domain::control
