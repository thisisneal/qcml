from qc_ply import yacc
from qc_lex import QCLexer
from qc_ast import isconstant, \
    Constant, Parameter, Variable, \
    Add, Negate, Mul, Transpose, \
    Objective, RelOp, Program, \
    ToVector, ToMatrix, Atom, \
    Neither, Positive, Negative, Node, \
    Shape, Scalar, Vector, Matrix, isscalar
from utils import create_shape_from_dims, \
    constant_folding_add, \
    constant_folding_mul, \
    negate_node, distribute

# our own exception class
class QCError(Exception): pass

def _find_column(data,pos):
    last_cr = data.rfind('\n',0,pos)
    if last_cr < 0:
      last_cr = 0
    column = (pos - last_cr) + 1
    return column

class QCParser(object):
    """ QCParser parses QCML but does not perform rewriting.
    
        After parsing, the resulting program is rewritten using our
        rewriting rules.
        
        To perform code generation, we walk the rewritten tree
    """
    def __init__(self):
        self.lex = QCLexer();
        self.lex.build();
        self.tokens = self.lex.tokens
        self.parser = yacc.yacc(module = self)
        
        self._dimensions = set()
        self._variables = {}
        self._parameters = {}
        
    def parse(self, text):
        """ Parses QCML and returns an AST.
        
            text:
                A string containing QCML source
        
            XXX / note to self: the AST is traversed afterwards to be
            rewritten. a problem is just a collection of ASTs
        """
        
        # append a newline if one doesn't exist at the end
        if('\n' != text[-1]):
            text += '\n'
        
        try:
            return self.parser.parse(text, debug=False)
        except QCError:
            pass
        except Exception as e:
            self._print_err(e, False)
    
    def _print_err(self, msg, raise_error=True):
        """ Prints a QCML parse error.
        
            msg:
                A string containing the message we want to print.
            
            offset:
                An integer for the line offset
        """
        # get the entire string we just tried to parse
        data = self.lex.lexer.lexdata
        s = data.split('\n')
        # check if the current token is a newline
        current_token = self.lex.lexer.lexmatch.lastgroup
        lexpos = self.lex.lexer.lexpos
        if current_token == 't_NL':
            print "arr"
            offset = 2
            lexpos -= 20
        else:
            offset = 1
        
        # if token:
#             print token
#             print token.type
#             
#             num = token.lineno
#             pos = _find_column(data, token.lexpos)
#             
#         else:
        num = self.lex.lexer.lineno - offset + 1
        line = s[num - 1]

        leader = 2*' '
        print "QCML error on line %s:" % num
        #print
        #print leader, """   ... """
        #print leader, """   %s """ % s[ind - 1].lstrip().rstrip()
        print leader, """>> %s """ % line.lstrip().rstrip()
        #print leader, """   %s """ % s[ind + 1].lstrip().rstrip()
        #print leader, """   ... """
        print
        print "Error:", msg
        print
        
        if raise_error:
            raise QCError(msg)
    
    def _name_exists(self,s):
        return (s in self._variables.keys() or s in self._parameters.keys() or s in self._dimensions)
        
    precedence = (
        ('left', 'PLUS', 'MINUS'),
        ('left', 'TIMES', 'DIVIDE'),
        ('right', 'UMINUS'),
        ('left', 'TRANSPOSE')
    )
    
    def p_program(self,p):
        """program : lines objective lines
                   | empty"""
        constraints = p[1]
        if p[3] is not None:
            constraints += p[3]
        p[0] = Program(p[2], constraints, self._variables, self._parameters, self._dimensions)
    
    def p_lines_line(self,p):
        """lines : declaration NL"""
        if(p[1] is not None):
            p[0] = p[1]
    
    def p_lines_many_line(self,p):
        'lines : lines declaration NL'
        if(p[1] is not None and p[2] is not None):
            p[0] = p[1] + p[2]
        elif(p[1] is None and p[2] is not None):
            p[0] = p[2]
        elif(p[1] is not None and p[2] is None):
            p[0] = p[1]
        else:
            pass
    
    def p_objective(self,p):
        '''objective : SENSE expression NL
                     | SENSE expression NL subject_to NL'''
        p[0] = Objective(p[1],p[2])
    
    def p_subject_to(self,p):
        'subject_to : SUBJ TO'
        pass
        
    
    def p_declaration(self,p):
        """declaration : create 
                       | constraint
                       | empty
        """
        # create returns None
        # constraint returns a list of constraints
        p[0] = p[1]
        
    
    def p_empty(self,p):
        'empty : '
        pass
    
    def p_create_dimension(self,p):
        """create : DIMENSION ID"""
        if self._name_exists(p[2]):
            self._print_err("name '%s' already exists in namespace" % p[2])
        else:
            self._dimensions.add(p[2])
    
    def p_create_dimensions(self,p):
        'create : DIMENSIONS idlist'
        self._dimensions = self._dimensions.union(p[2])
                
    def p_create_identifier(self,p):
        """create : VARIABLE array
                  | PARAMETER array
        """
        (name, shape) = p[2]
        if(p[1] == 'variable'):
            self._variables[name] = Variable(name, shape)
        if(p[1] == 'parameter'):
            self._parameters[name] = Parameter(name, shape, Neither())
    
    def p_create_identifiers(self,p):
        """create : VARIABLES arraylist
                  | PARAMETERS arraylist
        """
        if(p[1] == 'variables'):
            for (name, shape) in p[2]:
                self._variables[name] = Variable(name, shape)
        if(p[1] == 'parameters'):
            for (name, shape) in p[2]:
                self._parameters[name] = Parameter(name, shape, Neither())
    
    def p_create_signed_identifier(self,p):
        'create : PARAMETER array SIGN'
        (name, shape) = p[2]
        if p[3] == 'positive' or p[3] == 'nonnegative':
            self._parameters[name] = Parameter(name, shape, Positive())
        else:
            self._parameters[name] = Parameter(name, shape, Negative())
    
    def p_array_identifier(self,p):
        '''array : ID LPAREN dimlist RPAREN
                 | ID'''
        if self._name_exists(p[1]):
            self._print_err("name '%s' already exists in namespace" % p[1])
        else:
            if(len(p) == 2):
                shape = Scalar()
            else:
                shape = create_shape_from_dims(p[3])
            p[0] = (p[1],shape)        
    
    # (for shape) id, id, id ...
    def p_dimlist_list(self,p):
        'dimlist : dimlist COMMA ID'
        if(p[3] in self._dimensions):
            p[0] = p[1] + [p[3]]
        else:
            self._print_err("dimension '%s' not declared" % p[3])
    
    def p_dimlist_list_int(self,p):
        'dimlist : dimlist COMMA INTEGER'
        p[0] = p[1] + [p[3]]
    
    def p_dimlist_id(self,p):
        'dimlist : ID'
        if(p[1] in self._dimensions):
            p[0] = [p[1]]
        else:
            self._print_err("dimension '%s' not declared" % p[1])
    
    def p_dimlist_constant(self,p):
        'dimlist : INTEGER'
        p[0] = [p[1]]
    
    # (for declaring multiple dimensions) id id id ...
    def p_idlist_list(self,p):
        '''idlist : idlist ID'''
        if self._name_exists(p[2]):
            self._print_err("name '%s' already exists in namespace" % p[2])
        else:
            p[0] = p[1] + [p[2]]
    
    def p_idlist_id(self,p):
        'idlist : ID'
        if self._name_exists(p[1]):
            self._print_err("name '%s' already exists in namespace" % p[1])
        else:
            p[0] = [p[1]]
    
    # for declaring multiple variables, parameters
    def p_arraylist_list(self,p):
        '''arraylist : arraylist array'''
        p[0] = p[1] + [p[2]]
    
    def p_arraylist_array(self,p):
        'arraylist : array'
        p[0] = [p[1]]
    
    def p_constraint(self,p):
        '''constraint : expression EQ expression
                      | expression LEQ expression
                      | expression GEQ expression'''
        p[0] = [RelOp(p[2],p[1],p[3])]
    
    # more generic chained constraint is 
    #    constraint EQ expression
    #    constraint LEQ expression
    #    constraint GEQ expression
    # not sure if we need to handle that
    def p_chained_constraint(self,p):
        '''constraint : expression LEQ expression LEQ expression
                      | expression GEQ expression GEQ expression'''
        p[0] = [RelOp(p[2],p[1],p[3]), RelOp(p[4],p[3],p[5])]
    
    
    def p_expression_add(self,p):
        'expression : expression PLUS expression'
        # OK: performs constant folding
        # does not simplify x + 3x = 4x
        if str(p[1]) == str(p[3]):
            # x + x = 2x
            p[0] = Mul(Constant(2.0), p[1])
        else:
            p[0] = constant_folding_add(p[1],p[3])
    
    def p_expression_minus(self,p):
        'expression : expression MINUS expression'
        # OK: performs constant folding
        if str(p[1]) == str(p[3]):
            p[0] = Constant(0)
        else:
            p[0] = constant_folding_add(p[1], negate_node(p[3]))
    
    def p_expression_divide(self,p):
        'expression : expression DIVIDE expression'
        if isconstant(p[1]) and isconstant(p[3]):
            p[0] = Constant(p[1].value / p[3].value)
        else:
            self._print_err("cannot divide non-constants '%s' and '%s'" % (p[1],p[3]))
            
    def p_expression_multiply(self,p):
        'expression : expression TIMES expression'
        p[0] = distribute(p[1],p[3])
    
    def p_expression_group(self,p):
        'expression : LPAREN expression RPAREN'
        p[0] = p[2]
    
    def p_expression_negate(self,p):
        'expression : MINUS expression %prec UMINUS'
        p[0] = negate_node(p[2])
    
    def p_expression_transpose(self,p):
        'expression : expression TRANSPOSE'
        if isscalar(p[1]):
            p[0] = p[1]
        else:
            p[0] = Transpose(p[1])
    
    def p_expression_constant(self,p):
        """expression : CONSTANT
                      | INTEGER
                      | ID"""
        # these are leaves in the expression tree
        if isinstance(p[1], float):
            p[0] = Constant(p[1])
        elif isinstance(p[1], int):
            p[0] = Constant(float(p[1]))
        elif p[1] in self._variables.keys():
            p[0] = ToVector(self._variables[p[1]])
        elif p[1] in self._parameters.keys():
            p[0] = ToMatrix(self._parameters[p[1]])
        else:
            self._print_err("Unknown identifier '%s'" % p[1])
    
    def p_expression_atom(self,p):
        'expression : ATOM LPAREN arglist RPAREN'
        p[0] = Atom(p[1],p[3])
    
    def p_arglist(self, p):
        'arglist : arglist COMMA expression'
        p[0] = p[1] + [p[3]]
    
    def p_arglist_expr(self, p):
        'arglist : expression'
        p[0] = [p[1]]
    
    def p_dimlist_constant(self,p):
        'dimlist : INTEGER'
        p[0] = [p[1]]
    
    # (Super ambiguous) error rule for syntax errors
    def p_error(self,p):
        if(p is None):
            self._print_err("End of file reached")
        else:
            if p.type != 'NL':
                self._print_err("Syntax error at '%s'" % p.value)
            else:
                self._print_err("Syntax error at newline. Perhaps missing a constraint?")
