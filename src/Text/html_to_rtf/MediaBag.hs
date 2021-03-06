{-# LANGUAGE GeneralizedNewtypeDeriving, DeriveDataTypeable #-}

module Text.Pandoc.MediaBag (
                     MediaBag,
                     lookupMedia,
                     insertMedia,
                     mediaDirectory,
                     extractMediaBag
                     ) where
import System.FilePath
import qualified System.FilePath.Posix as Posix
import System.Directory (createDirectoryIfMissing)
import qualified Data.Map as M
import qualified Data.ByteString.Lazy as BL
import Control.Monad (when)
import Text.Pandoc.MIME (MimeType, getMimeTypeDef)
import qualified Text.Pandoc.UTF8 as UTF8
import Data.Maybe (fromMaybe)
import System.IO (stderr)
import Data.Data (Data)
import Data.Typeable (Typeable)

-- | A container for a collection of binary resources, with names and
-- mime types.  Note that a 'MediaBag' is a Monoid, so 'mempty'
-- can be used for an empty 'MediaBag', and '<>' can be used to append
-- two 'MediaBag's.
newtype MediaBag = MediaBag (M.Map [String] (MimeType, BL.ByteString))
        deriving (Monoid, Data, Typeable)

instance Show MediaBag where
  show bag = "MediaBag " ++ show (mediaDirectory bag)

-- | Insert a media item into a 'MediaBag', replacing any existing
-- value with the same name.
insertMedia :: FilePath       -- ^ relative path and canonical name of resource
            -> Maybe MimeType -- ^ mime type (Nothing = determine from extension)
            -> BL.ByteString  -- ^ contents of resource
            -> MediaBag
            -> MediaBag
insertMedia fp mbMime contents (MediaBag mediamap) =
  MediaBag (M.insert (splitDirectories fp) (mime, contents) mediamap)
  where mime = fromMaybe fallback mbMime
        fallback = case takeExtension fp of
                        ".gz"   -> getMimeTypeDef $ dropExtension fp
                        _       -> getMimeTypeDef fp

-- | Lookup a media item in a 'MediaBag', returning mime type and contents.
lookupMedia :: FilePath
            -> MediaBag
            -> Maybe (MimeType, BL.ByteString)
lookupMedia fp (MediaBag mediamap) = M.lookup (splitDirectories fp) mediamap

-- | Get a list of the file paths stored in a 'MediaBag', with
-- their corresponding mime types and the lengths in bytes of the contents.
mediaDirectory :: MediaBag -> [(String, MimeType, Int)]
mediaDirectory (MediaBag mediamap) =
  M.foldWithKey (\fp (mime,contents) ->
      (((Posix.joinPath fp), mime, fromIntegral $ BL.length contents):)) [] mediamap

-- | Extract contents of MediaBag to a given directory.  Print informational
-- messages if 'verbose' is true.
extractMediaBag :: Bool
                -> FilePath
                -> MediaBag
                -> IO ()
extractMediaBag verbose dir (MediaBag mediamap) = do
  sequence_ $ M.foldWithKey
     (\fp (_ ,contents) ->
        ((writeMedia verbose dir (Posix.joinPath fp, contents)):)) [] mediamap

writeMedia :: Bool -> FilePath -> (FilePath, BL.ByteString) -> IO ()
writeMedia verbose dir (subpath, bs) = do
  -- we join and split to convert a/b/c to a\b\c on Windows;
  -- in zip containers all paths use /
  let fullpath = dir </> normalise subpath
  createDirectoryIfMissing True $ takeDirectory fullpath
  when verbose $ UTF8.hPutStrLn stderr $ "pandoc: extracting " ++ fullpath
  BL.writeFile fullpath bs


