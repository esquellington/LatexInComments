/* laic BENCHMARK: 10 simple formulas, takes 0.7..1.0 sec
   Naked equations:
   inline \( \alpha = \beta \) formula
   \[ C = \|p_0-p_1\| = 0 \]
   Equation*
   \begin{equation*}
     I = \int_a^b f(\mathbf x) dx
   \end{equation*}
   Align*
   \begin{align*}
     \alpha &= ( \beta + \eta ) \\
     \gamma &= [ \delta - \nu ]
   \end{align*}
   Matrix:
   \[
   M = \begin{bmatrix}
        M_{xx} & M_{xy} & M_{xz} \\
        M_{yx} & M_{yy} & M_{yz} \\
        M_{zx} & M_{zy} & M_{zz} \\
        \end{bmatrix}
   \]
   Del operator
   \[ \nabla = (\frac{\partial}{\partial x},\frac{\partial}{\partial y},\frac{\partial}{\partial z}) \]
   Gradient
   \[ \nabla f = (\frac{\partial f}{\partial x},\frac{\partial f}{\partial y},\frac{\partial f}{\partial z}) \]
   Laplacian (Del squared)
   \[ \Delta f = \nabla^2 f = \nabla \cdot \nabla f\]
   Divergence
   \[ \text{div} \vec f = \nabla \cdot \vec f \]
   Curl
   \[ \text{curl} \vec f = \nabla \times \vec f\]
*/

/* laic BENCHMARK: SINGLE formula merging all 10 individual eq above, takes 0.08..0.09 sec (roughly 10x faster)
   \begin{align*}
     \alpha &= \beta \\
     C &= \|p_0-p_1\| = 0 \\
     I &= \int_a^b f(\mathbf x) dx \\
     \alpha &= ( \beta + \eta ) \\
     \gamma &= [ \delta - \nu ] \\
     M &= \begin{bmatrix}
        M_{xx} & M_{xy} & M_{xz} \\
        M_{yx} & M_{yy} & M_{yz} \\
        M_{zx} & M_{zy} & M_{zz} \\
        \end{bmatrix} \\
     \nabla &= (\frac{\partial}{\partial x},\frac{\partial}{\partial y},\frac{\partial}{\partial z}) \\
     \nabla f &=(\frac{\partial f}{\partial x},\frac{\partial f}{\partial y},\frac{\partial f}{\partial z}) \\
     \Delta f &= \nabla^2 f = \nabla \cdot \nabla f \\
     \text{div} \vec f &= \nabla \cdot \vec f \\
     \text{curl} \vec f &= \nabla \times \vec f \\
   \end{align*}
*/

//BUG Last LaTeX block in the file need to have at least 1 additional \[\alpha\]
//comment afterwards for (laic-create-overlays-from-comment-inside) to
//work, not sure why, but likely the func that finds the last point in
//a comment is failing, with "Wrong type argument: number-or-marker-p, nil"
