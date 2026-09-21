# Math

Marklens renders LaTeX with [KaTeX](https://katex.org), bundled offline. Formulas
are lifted out of the source before the markdown parser sees them, so backslashes,
underscores and braces survive intact.

## Inline

Euler's identity, $e^{i\pi} + 1 = 0$, sits in the run of text. So does a subscript
like $a_1 + b_2$ and a product like $a \times b$ — neither the `_` nor the `*` is
mistaken for emphasis.

## Display

$$\mathbf{ZAR\ 5,000,000.00}$$

$$
\int_0^\infty \frac{1}{x^2 + 1}\,dx = \frac{\pi}{2}
$$

$$
\begin{matrix}
a & b \\
c & d
\end{matrix}
$$

A deliberately wide one, to show that it scrolls rather than stretching the page:

$$
f(x) = a_0 + a_1x + a_2x^2 + a_3x^3 + a_4x^4 + a_5x^5 + a_6x^6 + a_7x^7 + a_8x^8 + a_9x^9 + a_{10}x^{10} + a_{11}x^{11} + a_{12}x^{12} + a_{13}x^{13} + a_{14}x^{14} + a_{15}x^{15} + a_{16}x^{16} + a_{17}x^{17} + a_{18}x^{18} + a_{19}x^{19} + a_{20}x^{20} + a_{21}x^{21} + a_{22}x^{22} + a_{23}x^{23}
$$

## What is *not* math

Prices stay prices: this costs $5 and that costs $10, and neither becomes a formula.

Nor does anything inside code. This stays literal:

```latex
$$\mathbf{ZAR\ 5,000,000.00}$$
```

And so does `$x + 1$` in an inline code span.

## When a formula is wrong

An unknown command renders in red with the source kept, rather than taking the
page down with it:

$$\notacommand{x}$$
