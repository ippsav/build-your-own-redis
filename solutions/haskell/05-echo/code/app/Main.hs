{-# OPTIONS_GHC -Wno-unused-top-binds #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Network.Simple.TCP (serve, HostPreference(HostAny), closeSock)
import Network.Socket.ByteString (recv, send)
import Control.Monad (forever, guard)
import Data.ByteString (ByteString, pack)
import qualified Data.ByteString.Char8 as B
import Prelude hiding (concat)
import Text.Megaparsec
    ( ParseErrorBundle,
      parse,
      count,
      (<|>),
      Parsec,
      MonadParsec(try),
      ParsecT,
      Stream(Tokens) )
import Text.Megaparsec.Byte ( crlf, printChar )
import Text.Megaparsec.Byte.Lexer (decimal)
import Data.Void ( Void )
import Data.Functor.Identity (Identity)
import Data.Either (fromRight)
import Data.Text ( toLower, Text )
import Data.Text.Encoding (decodeUtf8)

type Request = ByteString
type Response = ByteString
type Parser = Parsec Void Response
type Command = IO Response

main :: IO ()
main = do
    let port = "6379"
    putStrLn $ "\r\n>>> Redis server listening on port " ++ port ++ " <<<"
    serve HostAny port $ \(socket, _address) -> do
        putStrLn $ "successfully connected client: " ++ show _address
        _ <- forever $ do
            input <- recv socket 2048
            response <- parseInput input
            send socket (encodeRESP response)
        closeSock socket

encodeRESP :: Response -> Response
encodeRESP s = B.concat ["+", s, "\r\n"]

parseInput :: Request -> Command
parseInput req = fromRight err response
    where
        err = return "-ERR unknown command"
        response = parseRequest req

parseRequest :: Response
    -> Either (ParseErrorBundle Response Void) Command
parseRequest = parse parseInstruction ""

parseInstruction :: Parser Command
parseInstruction = try parseEcho
               <|> try parsePing

cmpIgnoreCase :: Text -> Text -> Bool
cmpIgnoreCase a b = toLower a == toLower b

crlfAlt :: ParsecT Void ByteString Identity (Tokens ByteString)
crlfAlt = "\\r\\n" <|> crlf

redisBulkString :: Parser Response
redisBulkString = do
    _ <- "$"
    n <- decimal
    guard $ n >= 0
    _ <- crlfAlt
    s <- count n printChar
    return $ pack s

commandCheck :: Text -> Parser (Integer, Response)
commandCheck c = do
    _ <- "*"
    n <- decimal
    guard $ n > 0
    cmd <- crlfAlt *> redisBulkString
    guard $ cmpIgnoreCase (decodeUtf8 cmd) c
    return (n, cmd)

parseEcho :: Parser Command
parseEcho = do
    (n, _) <- commandCheck "echo"
    guard $ n == 2
    message <- crlfAlt *> redisBulkString
    return $ echo message

parsePing :: Parser Command
parsePing = do
    (n, _) <- commandCheck "ping"
    guard $ n == 1
    return $ ping "PONG"

echo :: ByteString -> IO Response
echo = return

ping :: ByteString -> IO Response
ping = return
