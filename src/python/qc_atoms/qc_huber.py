import qc_square as square
from qc_base import abs_, abs_rewrite
from qcml.qc_ast import increasing, decreasing, nonmonotone, \
     Positive, Negative, ispositive, isnegative, \
     Convex, Concave, Affine, Constant, Atom, Variable
from utils import create_variable, annotate

""" This is the huber atom.

        huber(x) = minimize(w.^2 + 2*v) s.t. (abs(x) <= w + v; w<=1; v>=0)

    If x is a vector, it computes the elementwise huber.

    It is a CONVEX atom. It is NONMONOTONE in the first argument.

    If the first argument is POSITIVE, it is INCREASING in the first argument.
    If the first argument is NEGATIVE, it is DECRASING in the first argument.

    It returns a VECTOR expression.

    In every module, you must have defined two functions:
        attributes :: [arg] -> (sign, vexity, shape)
        rewrite :: [arg] -> Program
"""
def attributes(x):
    return square.attributes(x)

@annotate('huber')
def rewrite(p,x):
    """ Rewrite a quad_over_lin node

        p
            the parent node

        x, y
            the arguments
    """
    w = create_variable(p.shape)
    v = create_variable(p.shape)

    v1,d1 = abs_rewrite(p, x)
    v2,d2 = square.rewrite(p, w)

    constraints = d1 + d2 + [
        v1 <= w + v,
        w <= Constant(1),
        v >= Constant(0)
    ]

    return (v2 + Constant(2)*v, constraints)


