module Rewriter.Atoms (
  ecosSquare,
  ecosSqrt,
  ecosInvPos,
  
  ecosScalarPlusVector,
  ecosScalarTimesVector,
  ecosScalarMinusVector,
  ecosVectorMinusScalar,
  ecosPlus,
  ecosMinus,
  ecosNegate,
  ecosMul,
  ecosConcat,
  ecosAtoms) where
  
  import qualified Data.Map as M
  import Expression.Expression
  
  -- identity size function (for functions with single arguments)
  idSize x = x!!0
  scalarSize x = (1,1)
  
  isVector x = let (m,n) = x
    in n == 1
  isScalar x = let (m,n) = x
    in (m==1 && n == 1)
    
  -- list of valid atoms
  ecosAtoms = M.fromList [
    ("square", ecosSquare), 
    ("inv_pos", ecosInvPos),
    ("quad_over_lin", ecosQuadOverLin),
    ("pos", ecosPos),
    ("neg", ecosNeg),
    ("sqrt", ecosSqrt),
    ("geo_mean", ecosGeoMean),
    ("abs", ecosAbs),
    ("max", ecosMax),
    ("min", ecosMin),
    ("sum", ecosSum),
    ("norm", ecosNorm)]
    
  -- TODO: special cases scalar + vector, scalar - vector, scalar*vector?
  -- TODO: update max and min to only take vector arguments
  
  
  -- -- this might be one way to provide monotonicity
  -- squareMonotonicity :: [Sign]->[Monotonicity]
  -- squareMonotonicity [x] = [(monoQuadOverLin [x,Positive])!!0]
  -- 
  -- monoQuadOverLin :: [Sign] -> [Monotonicity]
  -- monoQuadOverLin [Positive, _] = [Increasing, Decreasing]
  -- monoQuadOverLin [Negative, _] = [Decreasing, Decreasing]
  -- monoQuadOverLin _ = [Nonmonotone, Decreasing]
  
  -- this is how you define atoms (they're defined independently at the moment)
  
  -- square(x) = x^2
  ecosSquare :: CVXSymbol
  ecosSquare = Atom {
    name="square",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=idSize,
    symbolVexity=Convex,
    symbolSign=positiveSign,
    monotonicity=(\x -> case(x) of
      [Positive] -> [Increasing]
      [Negative] -> [Decreasing]
      otherwise -> [Nonmonotone]
    ),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
            z1 = VarId (label out ++ "z1") m n
        in Problem (Just out) [
          [(out, Eye m "0.5"), (z0, Eye m "-1")],
          [(out, Eye m "-0.5"), (z1, Eye m "-1")]
        ] [Ones m "-0.5", Ones m "-0.5"] [SOCelem [z0,z1,inputs!!0]]
  )}
  
  -- inv_pos(x) = 1/x for x >= 0
  ecosInvPos :: CVXSymbol
  ecosInvPos = Atom {
    name="inv_pos",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),  -- XXX. can check if arg is positive
    symbolSize=idSize,
    symbolVexity=Convex,
    symbolSign=positiveSign,
    monotonicity=(\_ -> [Decreasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
            z1 = VarId (label out ++ "z1") m n
            one = VarId (label out ++ "z2") m n -- has to be vector for the SOC code to work (XXX/TODO: allow SOCelem with scalars)
            x = inputs!!0
        in Problem (Just out) [
          [(x, Eye m "0.5"), (out, Eye m "0.5"), (z0, Eye m "-1")],
          [(x, Eye m "0.5"), (out, Eye m "-0.5"), (z1, Eye m "-1")],
          [(one, Ones 1 "1")]
        ] 
        [Ones m "0", Ones m "0", Ones 1 "1"] 
        [SOCelem [z0,z1,one], SOCelem [x]]
  )}
  
  
  -- quad_over_lin(x,y) = x^Tx/y
  ecosQuadOverLin :: CVXSymbol
  ecosQuadOverLin = Atom {
    name="quad_over_lin",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> let (m,n) = x!!0
                            (p,q) = x!!1
                        in (n==1) && (p==1) && (q==1)),
    symbolSize=scalarSize,
    symbolVexity=Convex,
    symbolSign=positiveSign,
    monotonicity=(\x -> case (x) of
      [Positive, _] -> [Increasing, Decreasing]
      [Negative, _] -> [Decreasing, Decreasing]
      otherwise -> [Nonmonotone,Decreasing]
      ),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
            z1 = VarId (label out ++ "z1") m n
            x = inputs!!0
            y = inputs!!1
        in Problem (Just out) [
          [(y, Eye m "0.5"), (out, Eye m "0.5"), (z0, Eye m "-1")],
          [(y, Eye m "0.5"), (out, Eye m "-0.5"), (z1, Eye m "-1")]
        ] [Ones m "0", Ones m "0"] [SOC [z0,z1,x], SOCelem [y]]
    )}
    
  -- scalarPlusVector(x,y) = x*ones + y
  ecosScalarPlusVector :: CVXSymbol
  ecosScalarPlusVector = Atom {
    name="splus",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> isScalar (x!!0) && isVector (x!!1)),
    symbolSize=(\x->x!!1),
    symbolVexity=Affine,
    symbolSign=(\x -> case(x) of
      [Positive,Positive] -> Positive
      [Negative,Negative] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\x -> [Increasing, Increasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
        in Problem (Just out) [
          [(inputs!!0, Ones m "1"), (inputs!!1, Eye m "1"), (out, Eye m "-1")]
        ] [Ones m "0"] []
      )
  }
  
  
  -- plus(x,y) = x + y
  ecosPlus :: CVXSymbol
  ecosPlus = Atom {
    name="plus",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> let (m,n) = x!!0
                            (p,q) = x!!1
                        in (m==p) && (n==q)),
    symbolSize=idSize,  -- assumes parser created x+y where x,y have same size
    symbolVexity=Affine,
    symbolSign=(\x -> case(x) of
      [Positive,Positive] -> Positive
      [Negative,Negative] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\x -> [Increasing, Increasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
        in Problem (Just out) [
          [(inputs!!0, Eye m "1"), (inputs!!1, Eye m "1"), (out, Eye m "-1")]
        ] [Ones m "0"] []
      )
    }
  
  -- scalarMinusVector(x,y) = x*ones - y
  ecosScalarMinusVector :: CVXSymbol
  ecosScalarMinusVector = Atom {
    name="sminus",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> isScalar (x!!0) && isVector (x!!1)),
    symbolSize=(\x->x!!1),
    symbolVexity=Affine,
    symbolSign=(\x -> case(x) of
      [Positive,Negative] -> Positive
      [Negative,Positive] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\_ -> [Increasing, Decreasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            x = inputs!!0
            y = inputs!!1
        in Problem (Just out) [
          [ (x, Ones m "1"), (y, Eye m "-1"), (out, Eye m "-1")]
        ] [Ones m "0"] []
      )
  }

  -- vectorMinusScalar(x,y) = x - y*ones
  ecosVectorMinusScalar :: CVXSymbol
  ecosVectorMinusScalar = Atom {
    name="vminus",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> isScalar (x!!1) && isVector (x!!0)),
    symbolSize=(\x->x!!0),
    symbolVexity=Affine,
    symbolSign=(\x -> case(x) of
      [Positive,Negative] -> Positive
      [Negative,Positive] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\_ -> [Increasing, Decreasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            x = inputs!!0
            y = inputs!!1
        in Problem (Just out) [
          [(x, Eye m "1"), (y, Ones m "-1"), (out, Eye m "-1")]
        ] [Ones m "0"] []
      )
  }
  
  -- minus(x,y) = x - y
  ecosMinus :: CVXSymbol
  ecosMinus = Atom {
    name="minus",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> let (m,n) = x!!0
                            (p,q) = x!!1
                        in (m==p) && (n==q)),
    symbolSize=idSize, -- assumes parser created x-y where x,y have same size
    symbolVexity=Affine,
    symbolSign=(\x -> case(x) of
      [Positive,Negative] -> Positive
      [Negative,Positive] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\_ -> [Increasing, Decreasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
        in Problem (Just out) [
          [(inputs!!0, Eye m "1"), (inputs!!1, Eye m "-1"), (out, Eye m "-1")]
        ] [Ones m "0"] []
      )
    }
  
  -- negate(x) = -x
  ecosNegate :: CVXSymbol
  ecosNegate = Atom {
    name="negate",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=idSize,
    symbolVexity=Affine,
    symbolSign=(\x -> case(x) of
      [Positive] -> Negative
      [Negative] -> Positive
      otherwise -> Unknown
    ),
    monotonicity=(\_ -> [Decreasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
        in Problem (Just out) [
          [(inputs!!0, Eye m "-1"), (out, Eye m "-1")]
        ] [Ones m "0"] []
  )}
  
  -- pos(x) = max(x,0)
  ecosPos :: CVXSymbol
  ecosPos = Atom {
    name="pos",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=idSize,
    symbolVexity=Convex,
    symbolSign=positiveSign,
    monotonicity=(\_ -> [Increasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
        in Problem (Just out) [
          [(out, Eye m "1"), (inputs!!0, Eye m "-1"), (z0, Eye m "-1")]
        ] [Ones m "0"] [SOCelem [out], SOCelem [z0]]
      )
    }
    
  -- neg(x) = max(-x,0)
  ecosNeg :: CVXSymbol
  ecosNeg = Atom {
    name="neg",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=idSize,
    symbolVexity=Convex,
    symbolSign=positiveSign,
    monotonicity=(\_ -> [Decreasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
        in Problem (Just out) [
          [(out, Eye m "1"), (inputs!!0, Eye m "1"), (z0, Eye m "-1")]
        ] [Ones m "0"] [SOCelem [out], SOCelem [z0]]
      )
    }
    
  -- abs(x) = |x|
  ecosAbs :: CVXSymbol
  ecosAbs = Atom {
    name="abs",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=idSize,
    symbolVexity=Convex,
    symbolSign=positiveSign,
    monotonicity=(\x -> case(x) of
      [Positive] -> [Increasing]
      [Negative] -> [Decreasing]
      otherwise -> [Nonmonotone]),
    symbolRewrite=(\out inputs ->
      Problem (Just out) [] [] [SOCelem [out, inputs!!0]]
      )
    }
    
  -- norm2, norm1, norm_inf <-- not implemented since no vectors yet
  ecosNorm :: CVXSymbol
  ecosNorm = Atom {
    name="norm",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=scalarSize,
    symbolVexity=Convex,
    symbolSign=positiveSign,
    monotonicity=(\_ -> [Nonmonotone]),
    symbolRewrite=(\out inputs ->
      Problem (Just out) [] [] [SOC [out,inputs!!0]]
    )
    }
    
    
  -- sqrt(x) = geo_mean(x,1)
  ecosSqrt :: CVXSymbol
  ecosSqrt = Atom {
    name="sqrt",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=idSize,
    symbolVexity=Concave,
    symbolSign=positiveSign,
    monotonicity=(\_ -> [Increasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
            z1 = VarId (label out ++ "z1") m n
        in Problem (Just out) [
          [(inputs!!0, Eye m "0.5"), (z0, Eye m "-1")],
          [(inputs!!0, Eye m "-0.5"), (z1, Eye m "-1")]
        ] [Ones m "-0.5", Ones m "-0.5"] [SOCelem [z0,z1,out]]
    )
    }
  
  -- geo_mean(x,y) = sqrt(x*y)
  -- XXX: for now, geo_mean only takes scalar arguments
  ecosGeoMean :: CVXSymbol
  ecosGeoMean = Atom {
    name="geo_mean",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> (isScalar $ x!!0) && (isScalar $ x!!1)),
    symbolSize=scalarSize,
    symbolVexity=Concave,
    symbolSign=positiveSign,
    monotonicity=(\_ -> [Increasing, Increasing]),
    symbolRewrite=(\out inputs ->
        let z0 = VarId (label out ++ "z0") 1 1
            z1 = VarId (label out ++ "z1") 1 1
            -- negOut = -out; gives the right solution to maximization problem
            -- negOut = VarId $ (label out) ++ "z2"  
            x = inputs!!0
            y = inputs!!1
        in Problem (Just out) [
          [(x, Ones 1 "0.5"), (y, Ones 1 "0.5"), (z0, Ones 1 "-1")],
          [(x, Ones 1 "-0.5"), (y, Ones 1 "0.5"), (z1, Ones 1 "-1")]
        ] [Ones 1 "0", Ones 1 "0"] [SOC [z0,z1,out], SOC [inputs!!1]]
    )
    }
    
  -- pow_rat(x,p,q) <-- not implemented for the moment
  -- sum_largest(x,k) <-- also not implemented (uses LP dual)
  
  -- max(x,y)
  ecosMax:: CVXSymbol
  ecosMax = Atom {
    name="max",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> let (m,n) = x!!0
                            (p,q) = x!!1
                        in (m==p) && (n==q)),
    symbolSize=idSize,
    symbolVexity=Convex,
    symbolSign = (\x -> case(x) of
      [Positive,_] -> Positive
      [_,Positive] -> Positive
      [Negative,Negative] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\_ -> [Increasing, Increasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
            z1 = VarId (label out ++ "z1") m n
        in Problem (Just out) [
          [(out, Eye m "1"), (inputs!!0, Eye m "-1"), (z0, Eye m "-1")],
          [(out, Eye m "1"), (inputs!!1, Eye m "-1"), (z1, Eye m "-1")]
        ] [Ones m "0", Ones m "0"] [SOCelem [z0], SOCelem [z1]]
    )
    }
    
  -- min(x,y)
  ecosMin :: CVXSymbol
  ecosMin = Atom {
    name="min",
    nargs=2,
    nparams=0,
    areValidArgs=(\x -> let (m,n) = x!!0
                            (p,q) = x!!1
                        in (m==p) && (n==q)),
    symbolSize=idSize,
    symbolVexity=Concave,
    symbolSign = (\x -> case(x) of
      [Negative,_] -> Negative
      [_,Negative] -> Negative
      [Positive,Positive] -> Positive
      otherwise -> Unknown
    ),
    monotonicity=(\_ -> [Increasing, Increasing]),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            z0 = VarId (label out ++ "z0") m n
            z1 = VarId (label out ++ "z1") m n
        in Problem (Just out) [
          [(out, Eye m "-1"), (inputs!!0, Eye m "1"), (z0, Eye m "-1")],
          [(out, Eye m "-1"), (inputs!!1, Eye m "1"), (z1, Eye m "-1")]
        ] [Ones m "0", Ones m "0"] [SOCelem [z0], SOCelem [z1]]
    )
    }
  
  -- sum(x) = x_1 + x_2 + ... + x_n
  ecosSum :: CVXSymbol
  ecosSum = Atom {
    name="sum",
    nargs=1,
    nparams=0,
    areValidArgs=(\x -> isVector $ x!!0),
    symbolSize=scalarSize,
    symbolVexity=Affine,
    symbolSign = (\x -> case(x) of
      [Negative] -> Negative
      [Positive] -> Positive
      otherwise -> Unknown
    ),
    monotonicity=(\_ -> [Increasing]),
    symbolRewrite=(\out inputs ->
        let n = rows (inputs!!0)
            m = rows out
        in Problem (Just out) [
          [(inputs!!0, OnesT n "1"), (out, Ones m "-1")]
        ] [Ones m "0"] []
      )
    }
    
  -- this is how you define *parameterized* atoms

  -- mul(x; a) = a*x
  ecosMul :: CVXSymbol
  ecosMul = Atom {
    name="multiply",
    nargs=1,
    nparams=1,
    areValidArgs=(\x -> let (m,n) = x!!0
                            (p,q) = x!!1
                        in (m==q) && (n==1)),
    -- passes in [(n,1), (m,n)], returns (m,1)
    symbolSize=(\x -> let (m,n) = x!!0
                          (p,q) = x!!1
                      in (p,n)
    ),
    symbolVexity=Affine,
    symbolSign=(\x -> case (x) of
      [Positive, Positive] -> Positive
      [Negative, Negative] -> Positive
      [Positive, Negative] -> Negative
      [Negative, Positive] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\x -> case (x) of
      [_, Positive] -> [Increasing, Nonmonotone]
      [_, Negative] -> [Decreasing, Nonmonotone]
      otherwise -> [Nonmonotone, Nonmonotone]
    ),
    symbolRewrite=(\out inputs ->
        let m = rows (inputs!!1)
            n = cols (inputs!!1)
            s = label (inputs!!1)
        in Problem (Just out) [
          [(inputs!!0, Matrix (m,n) s), (out, Eye m "-1")]
        ] [Ones m "0"] []
      )
  }
  
  -- scalarTimesVector(x;a) = diag(a)*x
  ecosScalarTimesVector :: CVXSymbol
  ecosScalarTimesVector = Atom {
    name="stimes",
    nargs=1,
    nparams=1,
    areValidArgs=(\x -> isScalar (x!!1) && isVector (x!!0)),
    -- passes in [(n,1), (m,n)], returns (m,1)
    symbolSize=idSize,
    symbolVexity=Affine,
    symbolSign=(\x -> case (x) of
      [Positive, Positive] -> Positive
      [Negative, Negative] -> Positive
      [Positive, Negative] -> Negative
      [Negative, Positive] -> Negative
      otherwise -> Unknown
    ),
    monotonicity=(\x -> case (x) of
      [_, Positive] -> [Increasing, Nonmonotone]
      [_, Negative] -> [Decreasing, Nonmonotone]
      otherwise -> [Nonmonotone, Nonmonotone]
    ),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            s = label (inputs!!1)
        in Problem (Just out) [
          [(inputs!!0, Eye m s), (out, Eye m "-1")]
        ] [Ones m "0"] []
      )
  }
  
  -- special atoms for handling concatenation and (TODO: slicing)
  -- (vertical concatenation) [x; y; z; ...]
  ecosConcat :: Int->CVXSymbol
  ecosConcat nToConcat = Atom {
    name="concat",
    nargs=nToConcat,
    nparams=0,
    areValidArgs=(\x -> case (x) of
      [] -> True
      [x] -> True
      x -> let (m,n) = x!!0
        in (all (==n) (map snd x))
    ),
    -- passes in [(n,1), (m,n)], returns (m,1)
    symbolSize=(\x -> case(x) of
      [] -> (0,0)
      [x] -> x
      x ->
        let (m,n) = x!!0
            mtot = foldl (+) 0 (map fst x)
        in (mtot, n)
    ),
    symbolVexity=Affine,
    symbolSign=(\x -> if(all (==Positive) x) then Positive
      else if (all (==Negative) x) then Negative
      else Unknown
    ),
    monotonicity=(\x -> take nToConcat (repeat Increasing)),
    symbolRewrite=(\out inputs ->
        let m = rows out
            n = cols out
            mInputs = map rows inputs
            coeffs = zip inputs (map (flip Eye "1") mInputs)
        in Problem (Just out) [
          (out, Eye m "-1"):coeffs  -- the *first* of this list *must* be the variable to write *out* (otherwise the code will break)
        ] [Ones m "0"] []
      )
  }