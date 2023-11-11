module TSL.Command.Synthesize.Options where

data Options = Options
  { inputFile :: Maybe FilePath,
    outputFile :: Maybe FilePath,
    target :: Maybe String
  }