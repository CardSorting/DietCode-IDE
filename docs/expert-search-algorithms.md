# Expert-Tier: Search Algorithms & Optimizations

The `FindInFile` subsystem (`src/search/FindInFile.cpp`) is a critical performance path, especially during agent-triggered workspace-wide searches.

## 🧵 Line-By-Line Traversal

DietCode utilizes the line-based structure of its `TextBuffer` to implement a highly cache-friendly search algorithm.

- **Iterative Scanning**: Instead of searching a massive monolithic string, the engine iterates over the `std::vector<std::string>`. This ensures that each search step operates on a contiguous memory block that fits within L1/L2 caches.
- **Early Exit**: Searching is naturally bounded by line count, allowing for easy integration with pagination and cancellation signals.

## ⚡ Case-Insensitivity Optimization

Standard `std::string::find` is case-sensitive. To implement case-insensitive matching without the massive overhead of `std::locale` or full Unicode folding, DietCode uses a **Lower-Ascii Normalization Strategy**:

1. **`toLowerAscii`**: A custom utility in `src/utils/StringUtils.hpp` that performs a single-pass conversion of `[A-Z]` to `[a-z]`.
2. **Double Normalization**: Both the query (needle) and the line (haystack) are normalized once per search.
3. **Avoid Copying**: For case-sensitive searches, the engine uses the `originalLine` directly, avoiding any temporary string allocations.

---

## 🏗️ Algorithmic Complexity

- **Time Complexity**: $O(L \cdot (H + N))$, where $L$ is the number of lines, $H$ is the average line length, and $N$ is the query length.
- **Space Complexity**: $O(H)$ for the temporary normalized haystack during case-insensitive searches.

## 🛠️ Future Improvements for Experts

Contributors looking to further optimize the engine should explore:
- **Boyer-Moore / Horspool**: Implementing a more sophisticated substring search for very large queries.
- **SIMD Normalization**: Using AVX/SSE instructions to accelerate the `toLowerAscii` pass.
- **Mmap-backed Grep**: For files not currently open in the editor, bypassing the buffer entirely for raw disk-speed searches.
