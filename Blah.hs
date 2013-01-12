module Blah (
    runRepl,
    runScript
) where

import Control.Monad.Trans.Error (catchError)

import qualified System.IO as IO
import qualified Data.Map as Map

import Failure
import State
import Functions
import Tokenizer (tokenize)
import Parser (parse, Decl(..))
import Converters (toStr)
import Runner (runLine)

runRepl :: IO ()
runRepl = run repl replRuntime >> return ()
    where replRuntime = newRuntime IO.stdin sysFuncs

repl :: Runtime ()
repl = replRest

replRest :: Runtime ()
replRest = replLine []

replLine :: [Decl] -> Runtime ()

replLine [(Dl line)]  = replError (runLine line replShowLine) >> replRest
    where replError state = state `catchError` writeLine
          replShowLine val = toStr val >>= writeLine

replLine (line@((Dl _):_)) = replLine (Dnewline:line)

replLine unmatched = do
        isEof <- isEOF
        if isEof
        then if null unmatched
             then return ()
             else replFail "unmatched decls at end of input"
        else parseError parseRestLine >>= replLine
    where parseRestLine = tokenize >>= parse unmatched
          parseError state = state `catchError` handleError
          handleError errorMessage = writeLine errorMessage >> return []

replFail :: String -> Runtime ()
replFail = writeLine . ("<repl> " ++)

runScript :: IO.Handle -> IO ()
runScript file = parseScript >>= runOrShowError . verifyAST
    where parseScript = run scriptParse (newRuntime file Map.empty)
          runOrShowError (Left message) = putStrLn message
          runOrShowError (Right decls)  = runAST decls >> return ()
          runAST decls = run (script decls) (newRuntime IO.stdin sysFuncs)

scriptParse :: Runtime [Decl]
scriptParse = scriptParseLine []

scriptParseLine :: [Decl] -> Runtime [Decl]
scriptParseLine rest@((Dl _):_) = scriptParseLine (Dnewline:rest)
scriptParseLine decls = do isEof <- isEOF
                           if isEof
                           then return decls
                           else do tokens <- tokenize
                                   newDecls <- parse decls tokens
                                   scriptParseLine newDecls

-- verifies that there are only line and newline decls
verifyAST :: Either Failure [Decl] -> Either Failure [Decl]
verifyAST (Right decls)
    | all isValidDecl decls    = return decls
    | otherwise                = scriptFail "invalid decl"
    where isValidDecl (Dl _)   = True
          isValidDecl Dnewline = True
          isValidDecl _        = False
          scriptFail        = Left . ("<script> " ++)
verifyAST errorMessage      = errorMessage

script :: [Decl] -> Runtime ()
script line = scriptLine line `catchError` writeLine

scriptLine :: [Decl] -> Runtime ()
scriptLine []               = return ()
scriptLine (Dnewline:rest)  = script rest
scriptLine ((Dl line):rest) = runLine line ignore >> script rest
    where ignore val = return ()
scriptLine (decl:rest)  = error $ "unexpected decl in script: " ++ (show decl)

