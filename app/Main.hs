{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Api.Application (app)
import Api.AppServices (appServices)
import Api.Config (api, apiPort, configCodec, connectionString, database, getPort)

-- base
import Control.Exception (catch, SomeException)
import Data.Maybe (fromMaybe)
import Prelude hiding (writeFile)

-- bytestring
import Data.ByteString.Char8 (writeFile, unpack)

-- hasql
import Hasql.Connection (acquire)

-- jose
import Crypto.JOSE.JWK (JWK)

-- servant-auth-server
import Servant.Auth.Server (fromSecret, generateSecret, readKey)

-- toml
import Toml (decodeFileExact)

-- wai-extra
import Network.Wai.Middleware.RequestLogger (logStdoutDev)

-- warp
import Network.Wai.Handler.Warp (run)

main:: IO ()
main = do
  -- extract application configuration from `config.toml` file
  eitherConfig <- decodeFileExact configCodec "./config.toml"
  config <- either (\errors -> fail $ "unable to parse configuration: " <> show errors) pure eitherConfig
  -- acquire the connection to the database
  connection <- acquire $ connectionString (database config)
  either
    (fail . unpack . fromMaybe "unable to connect to the database")
    -- if we were able to connect to the database we run the application
    (\connection' -> do
      -- first we generate a JSON Web Key
      key <- jwtKey
      -- we setup the application services
      let services = appServices connection' key
      -- we retrieve the port from configuration
      let port = getPort . apiPort . api $ config
      -- eventually, we expose the application on the port, using the application services, logging requests on standard output
      run port . logStdoutDev . app $ services)
    connection

jwtKey :: IO JWK
jwtKey = do
  -- try to retrieve the JWK from file
  catch (readKey "./.jwk") $ \(_ :: SomeException) -> do
    -- if the file does not exist or does not contain a valid key, we generate one
    key <- generateSecret
    -- and we store it
    writeFile "./.jwk" key
    pure $ fromSecret key
