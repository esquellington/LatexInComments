// Short comment \[ \alpha < \beta \] ---> \[ \alpha < \beta \]
/* All supported LaTeX math block types

   Simple
   ------
   \( \alpha = \beta \) ---> \( \alpha = \beta \)
   \[ C = \|p_0-p_1\| = 0 \] ---> \[ C = \|p_0-p_1\| = 0 \]

   Equation/Equation*
   ------------------

   \begin{equation*}
     I = \int_a^b f(\mathbf x) dx
   \end{equation*}
   --->
   \begin{equation*}
     I = \int_a^b f(\mathbf x) dx
   \end{equation*}

   Align/Align*
   ------------

   \begin{align*}
     \alpha &= ( \beta + \eta ) \\
     \gamma &= [ \delta - \nu ]
   \end{align*}
   --->
   \begin{align*}
     \alpha &= ( \beta + \eta ) \\
     \gamma &= [ \delta - \nu ]
   \end{align*}
*/

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

// \[\alpha\]

/*
 \[\alpha\]
*/

/* Split vector \[v\] into normal \[v_n\] and tangential \[v_t\] components wrt a normal unit vector \[\hat n\]

   \[ v = v_n + v_t \]
   \[ v_n = \hat n \hat n^T v \]
   \[ v_t = (I - \hat n \hat n^T) v = v - v_n \]
*/

#include <list>
/* Compute average and variance for a list of floats in a single pass

   Average
   \[ \bar X = \frac{ \sum_i x_i}{N} \]

   Variance is the expected squared deviation from the average
   \[ \sigma^2 &= \frac{\sum_i (x_i-\bar X)^2}{N} \]

   We can reformulate the variance expression to allow computing it in
   a single pass, instead of a first pass to compute the average and a
   second pass for the variance using the average:
   \begin{align*}
    \sigma^2 &= \frac{\sum_i x_i^2 - 2 x_i \bar X + \bar X^2}{N} \\
             &= \frac{\sum_i x_i^2}{N} - \frac{\sum_i 2 x_i \bar X}{N} + \frac{\sum_i \bar X^2}{N} \\
             &= \frac{\sum_i x_i^2}{N} - 2\bar X\frac{\sum_i x_i}{N} + \frac{\sum_i \bar X^2}{N} \\
             &= \frac{\sum_i x_i^2}{N} - 2\bar X^2 + N\frac{\bar X^2}{N} \\
             &= \frac{\sum_i x_i^2}{N} - \bar X^2
   \end{align*}
*/
void ComputeAverageAndVariance( const std::list<float>& values,
                                float& average, float& variance )
{
    int N = 0;
    float sum_x = 0.0f;
    float sum_x2 = 0.0f;
    for( auto v : values )
    {
        N++;
        sum_x += v;
        sum_x2 += v * v;
    }
    average = sum_x / N; //\[\bar X\]
    variance = sum_x2 / N - average*average; //\[\sigma^2\]
}
