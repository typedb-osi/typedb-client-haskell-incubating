{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-} 
{-# LANGUAGE ScopedTypeVariables #-} 
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE RankNTypes #-}
module GraknClient where
import Network.GRPC.HighLevel.Generated
import Proto3.Suite.Types
import Options
import CoreDatabase
import Session
import qualified Query
import qualified Logic
import qualified Concept
import Transaction
import CoreService
import Data.Text (Text, pack, unpack)
import Data.Text.Lazy (toStrict, fromStrict)
import Control.Monad (void)
import Control.Monad.IO.Class
import Control.Concurrent
import qualified Data.ByteString as BS
import Control.Monad.Trans.Reader
import Network.GRPC.LowLevel.Op
import Network.GRPC.LowLevel.Call
import GHC.Exts
import GHC.Int
import Data.Vector (singleton)
import Unsafe.Coerce

defaultConfig :: ClientConfig
defaultConfig = ClientConfig { clientServerHost = "localhost"
                             , clientServerPort = 1729
                             , clientArgs = []
                             , clientSSLConfig = Nothing
                             , clientAuthority = Nothing
                             }

data GraknConfig = GraknConfig { clientConfig   :: ClientConfig
                               , timeoutSeconds :: Int }

defaultGrakn :: GraknConfig 
defaultGrakn = GraknConfig defaultConfig 3

newtype Keyspace = Keyspace { getKeyspace :: Text }
newtype GraknSession = GraknSession { getGraknSession :: BS.ByteString }

newtype GraknM m a = GraknM { fromGrakn :: ReaderT GraknConfig m a}
    deriving (Functor, Applicative, Monad)

newtype GraknError = GraknError { getError :: Text }
    deriving (Show)

openSession :: (MonadIO m) => Keyspace -> GraknM m (Either GraknError GraknSession)
openSession keyspace = 
    graknNormalRequestE
        graknCoreSessionOpen
        (Session_Open_Req db type' opts)
        (GraknSession . session_Open_ResSessionId)
    where
        db    = fromStrict $ getKeyspace keyspace
        type' = Enumerated $ Right $ Session_TypeDATA
        opts  = Just $ Options { optionsInferOpt = Nothing
                               , optionsTraceInferenceOpt = Nothing
                               , optionsExplainOpt = Nothing
                               , optionsParallelOpt = Nothing
                               , optionsPrefetchSizeOpt = Nothing
                               , optionsPrefetchOpt = Nothing
                               , optionsSessionIdleTimeoutOpt = Nothing
                               , optionsSchemaLockAcquireTimeoutOpt = Nothing
                               , optionsReadAnyReplicaOpt = Nothing } 



closeSession :: (MonadIO m) => GraknSession -> GraknM m (Either GraknError ())
closeSession (GraknSession session) = 
    graknNormalRequestE
        graknCoreSessionClose
        (Session_Close_Req session)
        (const ())


keyspaceExists :: MonadIO m => Keyspace -> GraknM m (Either GraknError Bool)
keyspaceExists(Keyspace keyspace) =
    graknNormalRequestE 
        graknCoreDatabasesContains 
        (CoreDatabaseManager_Contains_Req $ fromStrict keyspace) 
        coreDatabaseManager_Contains_ResContains

createKeyspace :: MonadIO m => Keyspace -> GraknM m (Either GraknError ())
createKeyspace (Keyspace keyspace) =
    graknNormalRequestE
        graknCoreDatabasesCreate
        (CoreDatabaseManager_Create_Req $ fromStrict keyspace)
        (const ())

deleteKeyspace :: MonadIO m => Keyspace -> GraknM m (Either GraknError ())
deleteKeyspace (Keyspace keyspace) =
    graknNormalRequestE
        graknCoreDatabaseDelete
        (CoreDatabase_Delete_Req $ fromStrict keyspace)
        (const ())

getKeyspaces :: MonadIO m => GraknM m (Either GraknError [Text])
getKeyspaces =
    graknNormalRequestE
        graknCoreDatabasesAll
        CoreDatabaseManager_All_Req
        (map toStrict . toList . coreDatabaseManager_All_ResNames)


networkLatency :: GHC.Int.Int32
networkLatency = 1000
tryTx :: GraknM IO (Either GraknError (StatusCode, StatusDetails))
tryTx = performTx $ map ($opts)  
                  $ [ openTx Transaction_TypeREAD Nothing networkLatency
                    , commitTx ]
    where opts = []


toTx opts a = Transaction_Req "reqId" (fromList opts) (Just a)
commitTx opts = toTx opts $ Transaction_ReqReqCommitReq Transaction_Commit_Req
rollbackTx opts = toTx opts $ Transaction_ReqReqRollbackReq Transaction_Rollback_Req
openTx txType opts lat txopts = toTx txopts $ Transaction_ReqReqOpenReq 
       $ Transaction_Open_Req 
            "randomTxID"
            (Enumerated $ Right txType)
            opts
            lat
                 
    {-
tryTx :: GraknM IO (Either GraknError ())
tryTx =  do
    void $ graknBidiRequestE
        graknCoreTransaction
        (\clientCall meta receive send done -> do 
            res <- send $ Transaction_Client $ singleton
                            $ Transaction_Req 
                                "reqID" 
                                (fromList []) 
                                $ Just $ Transaction_ReqReqOpenReq 
                              $ Transaction_Open_Req 
                                    "randomTxID"
                                    (Enumerated $ Right Transaction_TypeREAD)
                                    Nothing
                                    networkLatency
            print "tx should be open"
            print res
            
           
          --  res <- send $ Transaction_Client $ singleton
          --                  $ Transaction_Req 
          --                      "reqID" 
          --                      (fromList []) 
          --                      $ Just $ Transaction_ReqReqCommitReq 
          --                    $ Transaction_Commit_Req 
          --  print "tx should be committed"
          --  print res
        )-}
                {-
    return $ threadDelay 1000 
    return $ print "open fired"
    void $ graknBidiRequestE
        graknTransaction
        (\clientCall meta receive send done -> do 
            res <- send $ Transaction_Req (fromList [])
              $ Just $ Transaction_ReqReqCommitReq 
              $ Transaction_Commit_Req 
            print "should be committed"
            print res
            )
    --return $ GraknM $ (liftIO @(ReaderT GraknConfig _) $ print "commit fired")
    return $ Right ()-}

performTx :: MonadIO m => [Transaction_Req] ->  GraknM m (Either GraknError (StatusCode, StatusDetails))
performTx tx = graknBidiRequestE
                graknCoreTransaction
                (\clientCall meta receive send done -> do 
                    res <- send $ Transaction_Client $ fromList 
                            $ {- map toTransaction -} tx
                    return ()
                        {-
                    case (res :: Either GRPCIOError ()) of
                      Left err -> return $ Left $ GraknError $ pack $ show err
                      Right _  -> return $ Right ()
                      -}
                )

    {-
data API_ConecptManager = GetThingType { cm_thing_type_label :: Text }
                        | GetThing { cm_thing_id :: Text }
                        | PutEntityType { cm_put_entity_type_label :: Text }
                        | PutAttributeType { cm_put_attribute_type_label :: Text }
                        | PutRelationType { cm_put_relation_type_label :: Text }-} 

data GraknTx   = Open { txO_sessionID :: BS.ByteString
                      , txO_type :: Transaction_Type
                      , txO_options :: Maybe Options
                      , txO_latency :: Int32 }
               | Stream
               | Commit
               | Rollback
               | QueryManager { txQ_options :: Maybe Options
                              , txQ_qm :: Maybe Query.QueryManager_ReqReq }
               | ConceptManager { txCM_cm :: Maybe Concept.ConceptManager_ReqReq }
               | LogicManager { txL_lm :: Maybe Logic.LogicManager_ReqReq }
               | GetRule { ruleName :: Text, txR_rr :: Maybe Logic.Rule_ReqReq }
               | GetType { typeName :: Text, scope :: Text, txT_rr :: Maybe Concept.Type_ReqReq }
               | GetThing { thingId :: Text, txTh_rr :: Maybe Concept.Thing_ReqReq }

    {-
toTransaction :: GraknTx -> Transaction_Req
toTransaction a = Transaction_Req "randomTxID" (fromList [])
                    $ Just $ toTx a
    where toTx :: GraknTx -> Transaction_ReqReq
          toTx (Open sess t o l) = Transaction_ReqReqOpenReq $ Transaction_Open_Req sess (Enumerated $ Right t) o l
          toTx (Stream)          = Transaction_ReqReqStreamReq $ Transaction_Stream_Req
          toTx (Commit)          = Transaction_ReqReqCommitReq $ Transaction_Commit_Req
          toTx (Rollback)        = Transaction_ReqReqRollbackReq $ Transaction_Rollback_Req
          toTx (QueryManager o q)= Transaction_ReqReqQueryManagerReq $ Query.QueryManager_Req o q 
          toTx (ConceptManager m)= Transaction_ReqReqConceptManagerReq $ Concept.ConceptManager_Req m
          toTx (LogicManager lm) = Transaction_ReqReqLogicManagerReq $ Logic.LogicManager_Req  lm
          toTx (GetRule name req)    = Transaction_ReqReqRuleReq $ Logic.Rule_Req (fromStrict name) req
          toTx (GetType name scope req)    = Transaction_ReqReqTypeReq $ Concept.Type_Req (fromStrict name) (fromStrict scope) req
          toTx (GetThing thingId req)    = Transaction_ReqReqThingReq $ Concept.Thing_Req (fromString $ unpack thingId) req

-}


type Selector req res = GraknCore ClientRequest ClientResult
                -> ClientRequest 'Normal req res
                -> IO (ClientResult 'Normal res)

graknNormalRequestE :: MonadIO m => 
    Selector req res -> req -> (res -> a) -> GraknM m (Either GraknError a)
graknNormalRequestE select req convert = GraknM $ do
    (GraknConfig config timeoutSeconds) <- ask
    liftIO $ withGRPCClient config $ \client -> do
        graknFunction <- select <$> graknCoreClient client
        res <- graknFunction (ClientNormalRequest req timeoutSeconds [])
        case res of
            ClientNormalResponse 
              result 
              _meta1 _meta2 _status _details  -> return $ Right $ convert result
            ClientErrorResponse err -> return $ Left $ GraknError $ pack $ show err
            --_                       -> return $ Left $ GraknError $ "implementation error"

--  ClientBiDiRequest :: TimeoutSeconds -> MetadataMap ->
--  (LL.ClientCall -> MetadataMap -> StreamRecv response -> 
--      StreamSend request -> WritesDone -> IO ())
--
--      -> ClientRequest 'BiDiStreaming request response

type BidiSelector req res = GraknCore ClientRequest ClientResult
                                -> ClientRequest 'BiDiStreaming req res
                                -> IO (ClientResult 'BiDiStreaming res)
type HandlerFunction req res = ClientCall -> MetadataMap
                        -> StreamRecv res
                        -> StreamSend req
                        -> WritesDone -> IO ()
                        
graknBidiRequestE :: MonadIO m => 
    BidiSelector req res -> HandlerFunction req res -> GraknM m (Either GraknError (StatusCode, StatusDetails))
graknBidiRequestE select handler = GraknM $ do
    (GraknConfig config timeoutSeconds) <- ask
    liftIO $ withGRPCClient config $ \client -> do
        graknFunction <- select <$> graknCoreClient client
        res <- graknFunction (ClientBiDiRequest timeoutSeconds [] handler)
        case res of
            ClientBiDiResponse _meta _status _detail
                                    -> return $ Right $ (_status, _detail)
            ClientErrorResponse err -> return $ Left $ GraknError $ pack $ show err
            --_                       -> return $ Left $ GraknError $ "implementation error"




    {-
class MonadIO m => GraknAdmin m where
    dbContainsKeyspace :: Text -> m Bool
    dbCreateKeyspace   :: Text -> m ()
    dbGetKeyspaces     :: Text -> m ()
    dbDeleteKeyspaces  :: Text -> m ()
    openSession :: ClientConfig -> Keyspace
                    -> m a 
                    -> Either (m Error) (m ())
    closeSession :: m a -> m ()

class (Monad m) => GraknClient m where
    run :: Query result -> m a -> m q
    compute :: Computation result -> m a -> m result

-}






-- safer combinator-style
runWith :: MonadIO m => GraknM m a -> GraknConfig -> m a
runWith g config = runReaderT (fromGrakn g) config

withSession :: (MonadIO m) => Keyspace -> GraknM m a -> GraknM m (Either GraknError a)
withSession keyspace m = do
    sess <- openSession keyspace
    case sess of
      (Left x) ->
        return $ Left x
      (Right session) -> do
        res <- m
        closeSession session
        return $ Right res

    {-
actualClient :: IO ()
actualClient = withGRPCClient defaultConfig $ \client -> do
    (GraknCore dbContains dbCreate dbAll dbSchema dbDelete openSession closeSession pulseSession transaction) <- graknCoreClient client
    let db = "db"
        type' = Enumerated $ Right $ Session_TypeDATA
        opts  = Just $ Options Nothing Nothing Nothing 
    print $ "opening session with " 
             <> (show $ clientServerHost defaultConfig) 
             <> ":" <> (show $ clientServerPort defaultConfig)
    ClientNormalResponse (Session_Open_Res session openDuration) _meta1 _meta2 _status _details
        <- openSession (ClientNormalRequest (Session_Open_Req db type' opts) 1 [])
    print $ "doing stuff with open session " <> session
    print $ "closing session"
    ClientNormalResponse (_) _meta1 _meta2 _status _details
        <- closeSession (ClientNormalRequest (Session_Close_Req session) 1 [])
    print $ "closed session"

-}