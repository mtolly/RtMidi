{-# LANGUAGE ForeignFunctionInterface #-}

module Sound.RtMidi (
      Device(..)
    , Api(..)
    , apiSize
    , compiledApis
    , openPort
    , openVirtualPort
    , closePort
    , portCount
    , portName
    , defaultInput
    , createInput
    , setCallback
    , setCallbackWithUserData
    , cancelCallback
    , ignoreTypes
    , getMessage
    , defaultOutput
    , createOutput
    , sendMessage
    , closeInput
    , closeOutput
    , currentApi
    ) where

import Control.Monad
import Foreign
import Foreign.C
import Foreign.C.String

data Device = Input (Ptr ()) | Output (Ptr ())

device :: Device -> Ptr ()
device (Input x) = x
device (Output x) = x

toInput :: Device -> Ptr ()
toInput (Input x) = x

toOutput :: Device -> Ptr ()
toOutput (Output x) = x

data Api
  = UnspecifiedApi
  | CoreMidiApi
  | AlsaApi
  | JackApi
  | MultimediaApi
  | KernelStreamingApi
  | DummyApi
  deriving (Eq, Show)

instance Enum Api where
  fromEnum UnspecifiedApi = 0
  fromEnum CoreMidiApi = 1
  fromEnum AlsaApi = 2
  fromEnum JackApi = 3
  fromEnum MultimediaApi = 4
  fromEnum DummyApi = 5
  toEnum 0 = UnspecifiedApi
  toEnum 1 = CoreMidiApi
  toEnum 2 = AlsaApi
  toEnum 3 = JackApi
  toEnum 4 = MultimediaApi
  toEnum 5 = DummyApi

data ErrorType
  = Warning
  | DebugWarning
  | UnspecifiedError
  | NoDevicesFound
  | InvalidDevice
  | MemoryError
  | InvalidParameter
  | InvalidUse
  | DriverError
  | SystemError
  | ThreadError
  deriving (Eq, Show)


foreign import ccall "rtmidi_c.h rtmidi_sizeof_rtmidi_api"
   rtmidi_sizeof_rtmidi_api :: IO CInt


foreign import ccall "rtmidi_c.h rtmidi_get_compiled_api"
   rtmidi_get_compiled_api :: Ptr (Ptr CInt) -> IO CInt

foreign import ccall "rtmidi_c.h rtmidi_error"
   rtmidi_error :: CInt -> CString -> IO ()


foreign import ccall "rtmidi_c.h rtmidi_open_port"
   rtmidi_open_port :: Ptr () -> CInt -> CString -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_open_virtual_port"
   rtmidi_open_virtual_port :: Ptr () -> CString -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_close_port"
   rtmidi_close_port :: Ptr () -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_get_port_count"
   rtmidi_get_port_count :: Ptr () -> IO CInt

foreign import ccall "rtmidi_c.h rtmidi_get_port_name"
   rtmidi_get_port_name :: Ptr () -> CInt -> IO CString


foreign import ccall "rtmidi_c.h rtmidi_in_create_default"
   rtmidi_in_create_default :: IO (Ptr ())

foreign import ccall "rtmidi_c.h rtmidi_in_create"
   rtmidi_in_create :: CInt -> CString -> CInt -> IO (Ptr ())

foreign import ccall "rtmidi_c.h rtmidi_in_free"
   rtmidi_in_free :: Ptr () -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_in_get_current_api"
   rtmidi_in_get_current_api :: Ptr () -> IO CInt

foreign import ccall "rtmidi_c.h rtmidi_in_set_callback"
   rtmidi_in_set_callback :: Ptr () -> FunPtr (CDouble -> Ptr CUChar -> CInt -> Ptr () -> IO ()) -> Ptr () -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_in_cancel_callback"
   rtmidi_in_cancel_callback :: Ptr () -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_in_ignore_types"
   rtmidi_in_ignore_types :: Ptr () -> Bool -> Bool -> Bool -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_in_get_message"
   rtmidi_in_get_message :: Ptr () -> Ptr (Ptr CUChar) -> Ptr CSize -> IO CDouble

foreign import ccall "rtmidi_c.h rtmidi_out_create_default"
   rtmidi_out_create_default :: IO (Ptr ())

foreign import ccall "rtmidi_c.h rtmidi_out_create"
   rtmidi_out_create :: CInt -> CString -> IO (Ptr ())

foreign import ccall "rtmidi_c.h rtmidi_out_free"
   rtmidi_out_free :: Ptr () -> IO ()

foreign import ccall "rtmidi_c.h rtmidi_out_get_current_api"
   rtmidi_out_get_current_api :: Ptr () -> IO CInt

foreign import ccall "rtmidi_c.h rtmidi_out_send_message"
   rtmidi_out_send_message :: Ptr () -> Ptr CUChar -> CInt -> IO CInt


apiSize :: IO Int
apiSize = fromEnum <$> rtmidi_sizeof_rtmidi_api

-- |A static function to determine MIDI APIs built in.
compiledApis :: IO [Api]
compiledApis = fmap (map (toEnum . fromEnum)) $ do
   n <- fromIntegral <$> rtmidi_get_compiled_api nullPtr
   allocaArray n $ flip with $ \ptr -> do
      rtmidi_get_compiled_api ptr
      peekArray n =<< peek ptr

-- TODO: rtmidi_error

-- |Open a MIDI connection
openPort :: Device
         -> Int          -- ^ port number
         -> String       -- ^ name for the application port that is used
         -> IO ()
openPort d n name = withCString name $ rtmidi_open_port (device d) (toEnum n)

-- |This function creates a virtual MIDI output port to which other software applications can connect.
--
-- This type of functionality is currently only supported by the Macintosh OS X, Linux ALSA and JACK APIs
-- (the function does nothing with the other APIs).
openVirtualPort :: Device -> String -> IO ()
openVirtualPort d name = withCString name $ rtmidi_open_virtual_port (device d)

-- |Close an open MIDI connection (if one exists).
closePort :: Device -> IO ()
closePort d = rtmidi_close_port $ device d

-- |Return the number of MIDI ports available to the device.
portCount :: Device -> IO Int
portCount d = fromIntegral <$> (rtmidi_get_port_count $ device d)

-- |Return a string identifier for the specified MIDI port number.
--
-- An empty string is returned if an invalid port specifier is provided. 
portName :: Device -> Int -> IO String
portName d n = peekCString =<< rtmidi_get_port_name (device d) (toEnum n)

-- |Default constructor for a device to use for input.
defaultInput :: IO Device
defaultInput = Input <$> rtmidi_in_create_default

-- |Create a new device to use for input.
createInput :: Api        -- ^ API to use
            -> String     -- ^ client name
            -> Int        -- ^ size of the MIDI input queue
            -> IO Device
createInput api clientName queueSizeLimit = Input <$>
   (withCString clientName $ \str -> rtmidi_in_create (toEnum $ fromEnum api) str (toEnum queueSizeLimit))

foreign import ccall "wrapper"
  wrap :: (CDouble -> Ptr CUChar -> CInt -> Ptr () -> IO ()) -> IO (FunPtr (CDouble -> Ptr CUChar -> CInt -> Ptr () -> IO ()))

proxy :: (CDouble -> [CUChar] -> Ptr () -> IO ()) -> (CDouble -> Ptr CUChar -> CInt -> Ptr () -> IO ())
proxy f t d s p = peekArray (fromIntegral s) d >>= \a -> f t a p

-- |Set a callback function to be invoked for incoming MIDI messages.
-- 
-- The callback function will be called whenever an incoming MIDI message is received.
-- While not absolutely necessary, it is best to set the callback function before opening a MIDI port to avoid leaving
-- some messages in the queue.
setCallback :: Device
            -> (CDouble -> [CUChar] -> IO ())  -- ^ Function that takes a timestamp and a MIDI message as arguments
            -> IO ()
setCallback d c = flip (rtmidi_in_set_callback (toInput d)) nullPtr =<< wrap (proxy ((const .) . c))


setCallbackWithUserData :: Device
                        -> (CDouble -> [CUChar] -> Ptr () -> IO ())
                        -> Ptr ()
                        -> IO ()
setCallbackWithUserData d c u = flip (rtmidi_in_set_callback (toInput d)) u =<< (wrap $ proxy c)

-- |Cancel use of the current callback function (if one exists).
--
-- Subsequent incoming MIDI messages will be written to the queue and can be retrieved with the `getMessage` function.
cancelCallback :: Device -> IO ()
cancelCallback d = rtmidi_in_cancel_callback (toInput d)

-- |Specify whether certain MIDI message types should be queued or ignored during input. 
--
-- By default, MIDI timing and active sensing messages are ignored during message input because of their
-- relative high data rates. MIDI sysex messages are ignored by default as well.
-- Variable values of "true" imply that the respective message type will be ignored.
ignoreTypes :: Device
            -> Bool       -- ^ SysEx messages
            -> Bool       -- ^ Time messages
            -> Bool       -- ^ Sense messages
            -> IO ()
ignoreTypes d sysex time sense = rtmidi_in_ignore_types (toInput d) sysex time sense

-- TODO: error handling
-- |Return data bytes for the next available MIDI message in the input queue and the event delta-time in seconds.
--
-- This function returns immediately whether a new message is available or not.
-- A valid message is indicated by whether the list contains any elements.
getMessage :: Device -> IO ([CUChar], Double)
getMessage d = alloca $ \m -> alloca $ \s -> do
   timestamp <- rtmidi_in_get_message (toInput d) m s
   size <- peek s
   message <- peekArray (fromIntegral size) =<< peek m
   return (message, toEnum $ fromEnum timestamp)

-- |Default constructor for a device to use for output.
defaultOutput :: IO Device
defaultOutput = Output <$> rtmidi_out_create_default

-- |Create a new device to use for output.
createOutput :: Api        -- ^ API to use
             -> String     -- ^ client name
             -> IO Device
createOutput api clientName = Output <$>
   (withCString clientName $ rtmidi_out_create (toEnum (fromEnum api)))

-- TODO: error handling
-- |Immediately send a single message out an open MIDI output port. 
sendMessage :: Device -> [CUChar] -> IO ()
sendMessage d m = withArrayLen m $
   \n ptr -> rtmidi_out_send_message (toOutput d) ptr (fromIntegral n) >> return ()

-- |If a MIDI connection is still open, it will be closed
closeInput (Input x) = rtmidi_in_free x

-- |Close any open MIDI connections
closeOutput (Output x) = rtmidi_out_free x

-- |Returns the specifier for the MIDI API in use
currentApi :: Device -> IO Api
currentApi d = (toEnum . fromEnum) <$>
   case d of
      Input x -> rtmidi_in_get_current_api x
      Output x -> rtmidi_out_get_current_api x

