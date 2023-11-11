{-# NamedFieldPuns #-}
module TSL.Command.Synthesize where

import Options.Applicative (Parser, ParserInfo, action, fullDesc, header, help, helper, info, long, metavar, optional, progDesc, short, strOption)
import TSL.Command.Synthesize.Options (Options (..))

optionsParserInfo :: ParserInfo Options
optionsParserInfo =
  info (helper <*> optionsParser) $
    fullDesc
      <> progDesc "Synthesize a TSL specification"
      <> header "tsl synthesize"

optionsParser :: Parser Options
optionsParser =
  Options
    <$> optional
      ( strOption $
          long "input"
            <> short 'i'
            <> metavar "FILE"
            <> help "Input file (STDIN, if not set)"
            <> action "file"
      )
    <*> optional
      ( strOption $
          long "output"
            <> short 'o'
            <> metavar "FILE"
            <> help "Output file (STDOUT, if not set)"
            <> action "file"
      )
    <*> optional
      ( strOption $
          long "target"
            <> short 't'
            <> metavar "TARGET"
            <> help "Generates code for TARGET"
      )

-- | Read input from file or stdin.
readInput :: Maybe FilePath -> IO String
readInput Nothing = getContents
readInput (Just filename) = readFile filename

synthesize :: Options -> IO ()
synthesize opts@Options {inputFile, outputFile, target} = do
  input <- readInput $ inputFile
  return ()

command :: ParserInfo (IO ())
command = synthesize <$> optionsParserInfo