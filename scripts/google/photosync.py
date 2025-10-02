#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "playwright",
#   "rich",
#   "python-dateutil",
#   "click",
#   "pydantic",
#   "sqlalchemy",
#   "loguru",
# ]
# ///

# Skip Playwright browser download since we use our own browser
import os
os.environ['PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD'] = 'true'

import asyncio
import time
import json
from datetime import datetime
import click
from pathlib import Path
from typing import Optional, List, Tuple, Dict, Any
from dataclasses import dataclass, asdict
from dateutil import parser
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError
from sqlalchemy import create_engine, Column, Integer, String, Boolean, DateTime, ForeignKey, UniqueConstraint, text
from sqlalchemy.orm import declarative_base, sessionmaker, relationship, Session
from sqlalchemy.sql import func
from loguru import logger

console = Console()

# Configuration constants
USER_DATA_DIR = "./brave_playwright_profile2"
BRAVE_EXECUTABLE = "/usr/bin/brave-browser"
DEFAULT_TIMEOUT = 10000
INFO_PANEL_TIMEOUT = 2000
ALBUM_NAVIGATION_DELAY = 0
IMAGE_NAVIGATION_DELAY = 0.05
DUPLICATE_THRESHOLD = 10
DUPLICATE_LOG_THRESHOLD = 4
MAX_ALBUMS = 0 
DATABASE_PATH = "photos.db"

# SQLAlchemy setup
Base = declarative_base()
engine = create_engine(f"sqlite:///{DATABASE_PATH}")
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
class Album(Base):
    """SQLAlchemy model for albums."""
    __tablename__ = "albums"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    gphoto_title = Column(String, unique=False, nullable=False)
    immich_title = Column(String, unique=False, nullable=True)
    items = Column(Integer)
    processed_items = Column(Integer, default=0)
    shared = Column(Boolean, default=False)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())
    gphoto_url = Column(String, unique=True, nullable=False)
    
    # Relationships
    photos = relationship("Photo", back_populates="album", cascade="all, delete-orphan")
    errors = relationship("Error", back_populates="album")
    users = relationship("User", secondary="album_users", back_populates="albums")
    
    def __repr__(self):
        return f"<Album(gphoto_title='{self.gphoto_title}', items={self.items}, shared={self.shared})>"

class User(Base):
    """SQLAlchemy model for users."""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    gphoto_name = Column(String, unique=True, nullable=False)
    immich_name = Column(String, unique=False, nullable=True)
    immich_email = Column(String, nullable=True)  # Email field, nullable for manual filling later
    created_at = Column(DateTime, default=func.now())
    
    # Relationships
    albums = relationship("Album", secondary="album_users", back_populates="users")
    photos = relationship("Photo", back_populates="user")
    
    def __repr__(self):
        return f"<User(gphoto_name='{self.gphoto_name}', immich_name='{self.immich_name}', immich_email='{self.immich_email}')>"

class Photo(Base):
    """SQLAlchemy model for photos."""
    __tablename__ = "photos"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    filename = Column(String, nullable=False)
    date_taken = Column(DateTime)
    album_id = Column(Integer, ForeignKey("albums.id", ondelete="CASCADE"))
    user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"))
    created_at = Column(DateTime, default=func.now())
    
    # Relationships
    album = relationship("Album", back_populates="photos")
    user = relationship("User", back_populates="photos")
    
    def __repr__(self):
        return f"<Photo(filename='{self.filename}', date_taken={self.date_taken})>"

class Error(Base):
    """SQLAlchemy model for errors."""
    __tablename__ = "errors"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    error_message = Column(String, nullable=False)
    album_id = Column(Integer, ForeignKey("albums.id", ondelete="SET NULL"))
    created_at = Column(DateTime, default=func.now())
    
    # Relationships
    album = relationship("Album", back_populates="errors")
    
    def __repr__(self):
        return f"<Error(error_message='{self.error_message[:50]}...')>"

class AlbumUser(Base):
    """SQLAlchemy model for album-user relationships."""
    __tablename__ = "album_users"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    album_id = Column(Integer, ForeignKey("albums.id", ondelete="CASCADE"))
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"))
    created_at = Column(DateTime, default=func.now())
    
    # Unique constraint to prevent duplicate relationships
    __table_args__ = (UniqueConstraint('album_id', 'user_id', name='unique_album_user'),)
    
    def __repr__(self):
        return f"<AlbumUser(album_id={self.album_id}, user_id={self.user_id})>"

STEALTH_ARGS = [
    "--disable-features=IsolateOrigins,site-per-process",
    "--disable-blink-features=AutomationControlled",
    #"--no-sandbox",
    "--disable-infobars",
    "--disable-extensions",
    "--start-maximized",
    "--new-window"
]

STEALTH_INIT_SCRIPT = """
Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
Object.defineProperty(navigator, 'languages', { get: () => ['en-US','en'] });
Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3,4,5] });
window.chrome = window.chrome || { runtime: {} };
"""

def get_db_session() -> Session:
    """Get a database session."""
    return SessionLocal()

def init_database() -> None:
    """Initialize the database with all required tables."""
    Base.metadata.create_all(bind=engine)
    
    # Check if we need to add the processed_items column to existing albums
    session = get_db_session()
    try:
        # Check if the processed_items column exists by trying to access it
        try:
            session.execute(text("SELECT processed_items FROM albums LIMIT 1"))
        except Exception:
            # Column doesn't exist, add it
            console.print("[yellow]Adding processed_items column to albums table...[/yellow]")
            session.execute(text("ALTER TABLE albums ADD COLUMN processed_items INTEGER DEFAULT 0"))
            session.commit()
            console.print("[green]Added processed_items column to albums table[/green]")
        # Create photos_with_album view
        create_photos_with_album_view()
        console.print("[green]Database initialized successfully[/green]")
    except Exception as e:
        console.print(f"[red]Error initializing database: {e}[/red]")
        raise e
    finally:
        session.close()

def insert_or_update_album(album_info: "AlbumInfo") -> int:
    """Insert or update an album and return its ID."""
    session = get_db_session()
    try:
        # Check if album exists
        existing_album = session.query(Album).filter_by(gphoto_url=album_info.href).first()
        
        if existing_album:
            # Update existing album
            existing_album.items = album_info.items
            existing_album.shared = album_info.shared
            existing_album.gphoto_url = album_info.href
            # Don't reset processed_items when updating album info
            existing_album.updated_at = func.now()
            album_id = existing_album.id
        else:
            # Create new album
            new_album = Album(
                gphoto_title=album_info.title,
                items=album_info.items,
                processed_items=0,  # Start with 0 processed items
                shared=album_info.shared,
                gphoto_url=album_info.href
            )
            session.add(new_album)
            session.flush()  # To get the ID
            album_id = new_album.id
        
        session.commit()
        return album_id
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()

def insert_or_update_user(gphoto_name: str) -> int:
    """Insert or update a user and return their ID."""
    session = get_db_session()
    try:
        # Check if user exists
        existing_user = session.query(User).filter_by(gphoto_name=gphoto_name).first()
        
        if existing_user:
            user_id = existing_user.id
        else:
            # Create new user
            new_user = User(gphoto_name=gphoto_name)
            session.add(new_user)
            session.flush()  # To get the ID
            user_id = new_user.id
        
        session.commit()
        return user_id
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()

def insert_photo(photo: "PictureInfo", user_id: None | int, album_id: int) -> Optional[int]:
    """Insert a photo and return its ID. Returns None if photo already exists."""
    filename = photo.filename
    date_taken = photo.date
    
    session = get_db_session()
    try:
        # Check if photo already exists
        existing_photo = session.query(Photo).filter_by(
            filename=filename, 
            album_id=album_id,
            user_id=user_id
        ).first()
        
        if existing_photo:
            return None
        
        # Create new photo
        new_photo = Photo(
            filename=filename,
            date_taken=date_taken,
            album_id=album_id,
            user_id=user_id
        )
        session.add(new_photo)
        session.flush()  # To get the ID
        photo_id = new_photo.id
        
        session.commit()
        return photo_id
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()

def insert_error(error_message: str, album_id: Optional[int] = None) -> int:
    """Insert an error and return its ID."""
    session = get_db_session()
    try:
        new_error = Error(
            error_message=error_message,
            album_id=album_id
        )
        session.add(new_error)
        session.flush()  # To get the ID
        error_id = new_error.id
        
        session.commit()
        return error_id
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()

def link_user_to_album(album_id: int, user_id: int) -> None:
    """Link a user to an album."""
    session = get_db_session()
    try:
        # Check if relationship already exists
        existing_link = session.query(AlbumUser).filter_by(
            album_id=album_id, 
            user_id=user_id
        ).first()
        
        if not existing_link:
            new_link = AlbumUser(album_id=album_id, user_id=user_id)
            session.add(new_link)
            session.commit()
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()

def album_exists(album_info: "AlbumInfo") -> bool:
    """Check if an album with the given gphoto_url exists."""
    session = get_db_session()
    try:
        album = session.query(Album).filter_by(gphoto_url=album_info.href).first()
        return album is not None
    finally:
        session.close()

def get_album_photos_count(album_id: int) -> int:
    """Get the number of photos for a given album."""
    session = get_db_session()
    try:
        count = session.query(Photo).filter_by(album_id=album_id).count()
        return count
    finally:
        session.close()

def update_album_processed_items(album_id: int, processed_count: int) -> None:
    """Update the processed_items count for an album."""
    session = get_db_session()
    try:
        album = session.query(Album).filter_by(id=album_id).first()
        if album:
            album.processed_items = processed_count
            album.updated_at = func.now()
            session.commit()
    except Exception as e:
        session.rollback()
        raise e
    finally:
        session.close()

def is_album_fully_processed(album_id: int) -> bool:
    """Check if an album is fully processed."""
    session = get_db_session()
    try:
        album = session.query(Album).filter_by(id=album_id).first()
        if album and album.items and album.processed_items is not None:
            return album.processed_items >= album.items
        return False
    finally:
        session.close()

def create_photos_with_album_view() -> None:
    """Create the photos_with_album view that joins album and user names."""
    session = get_db_session()
    try:
        # Drop the view if it exists to recreate it
        session.execute(text("DROP VIEW IF EXISTS photos_with_album"))
        
        # Create the view with joins to get album and user information
        # Users are aggregated into a JSON array of objects with gphoto_name, immich_name, and immich_email to have one entry per photo
        create_view_sql = """
        CREATE VIEW photos_with_album AS
        SELECT 
            p.id as photo_id,
            p.filename as photo_filename,
            p.date_taken as photo_date_taken,
            p.created_at as photo_created_at,
            a.id as album_id,
            a.gphoto_title as album_gphoto_title,
            a.immich_title as album_immich_title,
            a.items as album_items,
            a.processed_items as album_processed_items,
            a.shared as album_shared,
            a.gphoto_url as album_gphoto_url,
            json_group_array(
                json_object('gphoto_name', u.gphoto_name, 'immich_name', u.immich_name, 'immich_email', u.immich_email)
            ) FILTER (WHERE u.gphoto_name IS NOT NULL) as users
        FROM photos p
        LEFT JOIN albums a ON p.album_id = a.id
        LEFT JOIN album_users au ON a.id = au.album_id
        LEFT JOIN users u ON au.user_id = u.id
        GROUP BY p.id, p.filename, p.date_taken, p.created_at, 
                 a.id, a.gphoto_title, a.immich_title, a.items, a.processed_items, a.shared, a.gphoto_url
        ORDER BY p.album_id, p.date_taken DESC
        """
        
        session.execute(text(create_view_sql))
        session.commit()
        console.print("[green]Created photos_with_album view successfully[/green]")
    except Exception as e:
        session.rollback()
        logger.error(f"Error creating photos_with_album view: {e}")
        raise e
    finally:
        session.close()

def get_albums_from_db(limit: int = None, offset: int = 0) -> List[Tuple[int, str, str, int]]:
    """Get albums from database for processing.
    
    Returns:
        List of tuples (album_id, album_gphoto_url, album_gphoto_title, album_items)
    """
    session = get_db_session()
    try:
        query = session.query(Album.id, Album.gphoto_url, Album.gphoto_title, Album.items).order_by(Album.id)
        if limit:
            query = query.limit(limit).offset(offset)
        albums = query.all()
        return [(album.id, album.gphoto_url, album.gphoto_title, album.items) for album in albums]
    finally:
        session.close()

@dataclass
class PictureInfo:
    """Data class for individual picture information."""
    filename: str
    date: datetime
    shared_by: str
    album_title: str

@dataclass
class AlbumInfo:
    """Data class for album information."""
    title: str
    items: int
    shared: bool
    pictures: List[PictureInfo]
    href: str

@dataclass
class ProcessingResult:
    """Data class for overall processing results."""
    total_albums: int
    total_pictures: int
    albums_processed: List[AlbumInfo]
    errors: List[str]

class GooglePhotosScraper:
    """Main scraper class for Google Photos."""

    def __init__(self, login: bool = False, max_albums: int = 5, start_album: int = 1, album_fresh: bool = False, skip_existing: bool = True, albums_only: bool = False):
        self.login = login
        self.max_albums = max_albums
        self.start_album = start_album
        self.album_fresh = album_fresh
        self.skip_existing = skip_existing
        self.albums_only = albums_only
        self.context = None
        self.page = None

    async def setup_browser(self) -> None:
        """Initialize and setup the browser context."""
        Path(USER_DATA_DIR).mkdir(exist_ok=True)
        # Note: Browser context is now managed in scrape_albums_from_db()
        # This method just prepares the configuration
        pass
    

    async def get_album_info(self) -> AlbumInfo:
        """Extract album information from the current selection."""
        try:
            # Get the currently selected album element
            selected_element = await self.page.evaluate_handle('document.activeElement')
            children = await selected_element.query_selector_all("div")
            href = await selected_element.get_attribute('href')

            if len(children) < 2:
                raise ValueError("Could not find album information elements")

            album_title, description = (await children[1].inner_text()).split("\n", 1)
            console.print(f"[blue]Album Title:[/blue] {album_title}")
            #console.print(f"[blue]Description:[/blue] {description}")
            shared = "shared" in description.lower()
            console.print(f"[blue]Shared:[/blue] {shared}")
            items = int(description.split(" ")[0])
            console.print(f"[blue]Items:[/blue] {items}")

            return AlbumInfo(
                title=album_title,
                items=items,
                shared="shared" in description.lower(),
                href=href,
                pictures=[]
            )

        except Exception as e:
            logger.error(f"Error getting album info: {e}")
            raise

    async def get_picture_info(self, album_title: str) -> Optional[PictureInfo]:
        """Extract information from the current picture."""
        try:
            # Wait for info panel to be visible
            #await self.page.wait_for_selector('div[aria-label*="Filename"]', timeout=INFO_PANEL_TIMEOUT)

            # Extract filename
            filename = None
            cnt = 0
            while not filename and cnt < 6:
                cnt += 1
                filename = await self._get_text_safely('div[aria-label*="Filename"]', timeout=INFO_PANEL_TIMEOUT)
                if cnt == 5:
                    logger.error(f"Could not find filename after {cnt} attempts, next album.")
                    return None
                    
                if not filename:
                    logger.warning("Could not find filename, make page reload and try again")
                    await self.page.reload(wait_until="domcontentloaded") 
                    await asyncio.sleep(1.0 * cnt)
                    if cnt > 3:
                        console.print(f"[red]Could not find filename, please fix it manually an press Enter to continue (album: {album_title}).")
                        input()
                        

            # Extract date information
            date_text = await self._get_text_safely('div[aria-label*="Date taken"]', timeout=INFO_PANEL_TIMEOUT)
            time_element = await self.page.query_selector('span[aria-label*="Time taken"]')
            time_text = await time_element.inner_text() if time_element else "N/A"

            # Parse date
            date_obj, date_str = self._parse_date(f"{date_text} {time_text}")

            # Extract shared by information
            shared_by = await self._get_text_safely('div:text("Shared by")', timeout=INFO_PANEL_TIMEOUT)
            shared_by = shared_by.replace("Shared by", "").strip() if shared_by else "N/A"

            return PictureInfo(
                filename=filename,
                date=date_obj,
                shared_by=shared_by,
                album_title=album_title,
            )

        except Exception as e:
            logger.error(f"Getting picture info: {e}")
            return None

    async def _get_text_safely(self, selector: str, timeout: int = 2000) -> Optional[str]:
        """Safely extract text from an element with timeout."""
        start = time.perf_counter() * 1000
        while time.perf_counter() * 1000 - start < timeout:
            try:
                elements = await self.page.query_selector_all(selector)
                visible_elements = []
                for element in elements:
                    if await element.is_visible():
                        visible_elements.append(await element.inner_text())
                if len(visible_elements) > 1:
                    logger.debug(f"Multiple visible elements found for selector: {selector}")
                elif len(visible_elements) == 1:
                    return visible_elements[0]
            except PlaywrightTimeoutError:
                logger.warning(f"Timed out waiting for element: {selector}")
            await asyncio.sleep(0.05)
        return None

    def _parse_date(self, date_str: str) -> Tuple[datetime, str]:
        """Parse date string and return both datetime object and formatted string."""
        try:
            date_obj = parser.parse(date_str)
            date_formatted = date_obj.strftime("%d.%m.%y %H:%M")
            return date_obj, date_formatted
        except Exception as e:
            logger.warning(f"Error parsing date '{date_str}': {e}")
            return None, date_str


    async def process_album_from_db(self, album_id: int, album_gphoto_url: str, album_gphoto_title: str, album_items: int) -> AlbumInfo:
        """Process images from an album using its gphoto_url URL."""
        console.print(f"[green]Processing album from database: {album_gphoto_title}[/green]")
        
        # Check if album should be skipped BEFORE any navigation
        processed_images = 0
        # If album_fresh is True, ignore existing processed count and start from 0
        if self.skip_existing and not self.album_fresh:
            if is_album_fully_processed(album_id):
                console.print(f"[yellow]Skipping fully processed album: {album_gphoto_title}[/yellow]")
                # Create AlbumInfo object for return
                album_info = AlbumInfo(
                    title=album_gphoto_title,
                    items=album_items,
                    shared=False,  # We'll get this from DB if needed
                    pictures=[],
                    href=album_gphoto_url
                )
                return album_info
            elif album_items > 0:  # Only continue if we know the item count
                processed_images = get_album_photos_count(album_id)
                console.print(f"[blue]Continuing partially processed album: {album_gphoto_title} (has {processed_images}/{album_items} photos)[/blue]")
        elif self.album_fresh:
            console.print(f"[blue]Starting fresh processing for album: {album_gphoto_title} (ignoring existing processed count)[/blue]")
        
        # Navigate to the album URL - construct absolute URL from relative href
        if album_gphoto_url.startswith('./'):
            album_url = f"https://photos.google.com{album_gphoto_url[1:]}"
        elif album_gphoto_url.startswith('/'):
            album_url = f"https://photos.google.com{album_gphoto_url}"
        else:
            album_url = album_gphoto_url
            
        console.print(f"[blue]Navigating to album URL: {album_url}[/blue]")
        await self.page.goto(album_url)
        await self.page.wait_for_load_state("domcontentloaded")
        
        # Find and navigate to the first image
        console.print("[blue]Looking for first image in album...[/blue]")
        first_image_url = None
        cnt = 0
        
        while first_image_url is None and cnt < 5:
            cnt += 1
            try:
                # Look for the first a tag with aria-label containing "Photo -"
                first_image_element = await self.page.wait_for_selector(
                    'a[aria-label*="Photo -"]', 
                    timeout=5000
                )
                
                # Get the href attribute directly from the a tag
                first_image_url = await first_image_element.get_attribute('href')
                
                if first_image_url:
                    logger.debug(f"Found first image URL: {first_image_url}")
                    # Construct absolute URL if needed
                    if first_image_url.startswith('./'):
                        first_image_url = f"https://photos.google.com{first_image_url[1:]}"
                    elif first_image_url.startswith('/'):
                        first_image_url = f"https://photos.google.com{first_image_url}"
                    
                    # Navigate to the first image
                    logger.debug("Navigating to first image...")
                    await self.page.goto(first_image_url)
                    await self.page.wait_for_load_state("domcontentloaded")
                    break
                else:
                    console.print(f"[yellow]Attempt {cnt}: Could not get href from first image element[/yellow]")
                    
            except Exception as e:
                console.print(f"[yellow]Attempt {cnt}: Could not find first image element: {e}[/yellow]")
            
            if cnt < 5:
                await asyncio.sleep(1.0 * cnt)
                await self.page.reload(wait_until="domcontentloaded")
        
        if not first_image_url:
            console.print(f"[red]Could not find first photo for album {album_gphoto_title}, please fix it manually and press Enter to continue.")
            input()
            
        # Get picture info for the first image after navigation
        picture_info = await self.get_picture_info(album_gphoto_title)
        cnt = 0
        while picture_info is None and cnt < 5:
            cnt += 1
            await self.page.reload(wait_until="domcontentloaded")
            await asyncio.sleep(1.0 * cnt)
            #await self.keyboard_press('ArrowRight', delay=0.2 * cnt) # select 1st image
            #await self.keyboard_press('Enter', delay=0.8 * cnt) # open first photo
            await self.page.wait_for_load_state("domcontentloaded")
            picture_info = await self.get_picture_info(album_gphoto_title)
            if cnt > 3:
                console.print(f"[red]Could not find first photo for album {album_gphoto_title}, please fix it manually and press Enter to continue.")
                input()
        
        pictures = []
        last_filename = None
        duplicate_count = 0
        processed_users = set()
        
        # Skip check already done at the beginning of the method
        
        # Get current photo count to continue from where we left off
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console
        ) as progress:
            task = progress.add_task(
                f"Processing {album_gphoto_title}...",
                total=album_items,
                completed=processed_images
            )

            photo_position = 1
            while processed_images < album_items:
                # go to the correct photo position (needed if some where already processed)
                if photo_position < processed_images:
                    await self.keyboard_press('ArrowRight', delay=IMAGE_NAVIGATION_DELAY)
                    photo_position += 1
                    continue
                    
                try:
                    picture_info = await self.get_picture_info(album_gphoto_title)

                    if not picture_info:
                        logger.error("Could not extract info for current image")
                        break

                    # Check for duplicates to detect end of album
                    if picture_info.filename == last_filename and picture_info.filename != "N/A":
                        duplicate_count += 1
                        if duplicate_count >= DUPLICATE_LOG_THRESHOLD:
                            await asyncio.sleep(1)
                            logger.warning(f"Duplicate filename detected: {picture_info.filename} ({duplicate_count})")
                            console.print("[red]Press Enter to continue...[/red]")
                            input()

                        if duplicate_count >= DUPLICATE_THRESHOLD:
                            logger.error("Reached end of album before expected (duplicate threshold met)")
                            # we add the same name to the album
                            
                        else:
                            await asyncio.sleep(0.15)
                            continue
                        

                    # New picture found
                    last_filename = picture_info.filename
                    pictures.append(picture_info)
                    duplicate_count = 0

                    # Save to database
                    try:
                        if picture_info.shared_by and picture_info.shared_by != "N/A":
                            user_id = insert_or_update_user(picture_info.shared_by)
                            link_user_to_album(album_id, user_id)
                            processed_users.add(picture_info.shared_by)

                        # Insert photo
                        photo_id = insert_photo(picture_info, user_id=user_id, album_id=album_id)
                        
                        if photo_id is not None:
                            # Photo was successfully inserted (not a duplicate)
                            photo_position += 1
                            # Update processed items count
                            processed_images += 1
                            update_album_processed_items(album_id, processed_images)
                            
                            # Link user to album for shared photos
                            
                            # Display progress for successfully processed photo
                            progress.update(task, advance=1, description=
                                f"[green]{processed_images}/{album_items} - {picture_info.filename}[/green]")
                        else:
                            # Photo is a duplicate, skip it but continue processing
                            console.print(f"[yellow]Skipping duplicate photo: {picture_info.filename}[/yellow]")
                            
                    except Exception as e:
                        logger.error(f"Error saving picture to database: {e}")
                        insert_error(f"Error saving picture {picture_info.filename}: {e}", album_id)

                    # Navigate to next image (always advance, even for duplicates)
                    await self.keyboard_press('ArrowRight', delay=IMAGE_NAVIGATION_DELAY)

                except Exception as e:
                    logger.error(f"Error processing picture: {e}")
                    insert_error(f"Error processing picture in album {album_gphoto_title}: {e}", album_id)
                    break

        # Return to albums view
        await self.page.goto("https://photos.google.com/albums")
        await self.page.wait_for_load_state("domcontentloaded")
        
        # Create AlbumInfo object for return
        album_info = AlbumInfo(
            title=album_gphoto_title,
            items=album_items,
            shared=False,  # We'll get this from DB if needed
            pictures=pictures,
            href=album_gphoto_url
        )
        
        console.print(f"[green]Processed {len(pictures)} pictures from {album_gphoto_title}[/green]")
        if processed_users:
            console.print(f"[blue]Associated users: {', '.join(processed_users)}[/blue]")
        return album_info

    async def navigate_to_album(self, album_position: int) -> None:
        """Navigate to the next album using arrow keys."""
        console.print(f"[blue]Navigating to album {album_position}[/blue]")
        for _ in range(album_position ):
            await self.keyboard_press('ArrowRight', delay=ALBUM_NAVIGATION_DELAY)
        console.print(f"[blue]Done[/blue]")
            
    async def keyboard_press(self, key: str, delay: int | None = 0.2):
        logger.debug(f"Pressing key '{key}'")
        await self.page.keyboard.press(key)
        if delay is not None and delay > 0:
            await asyncio.sleep(delay)


    async def collect_albums(self, max_albums: int = None, start_album: int = 1) -> List[AlbumInfo]:
        """Collect albums from Google Photos UI and add them to database."""
        albums_processed = []
        
        # Navigate to Google Photos albums
        await self.page.goto("https://photos.google.com/albums")
        if self.login:
            click.confirm("Press Enter when logged in and on the albums site ...", default=True)
        else:
            await self.page.wait_for_load_state("domcontentloaded")
            await asyncio.sleep(1)

        console.print(f"[blue]Starting to collect {max_albums} albums from index {start_album}...[/blue]")
        
        # Navigate to the first album to process
        if start_album > 1:
            console.print(f"[yellow]Navigating to album index {start_album}...[/yellow]")
            await self.navigate_to_album(start_album - 2)  # Convert to 0-based and adjust for starting position
        
        prev_album: None | AlbumInfo = None
        for album_position in range(start_album - 1, start_album - 1 + max_albums):
            try:
                # Navigate to next album (only one step from current position)
                if album_position >= start_album - 1:
                    logger.debug(f"Navigating to album {album_position}... (start album: {start_album})")
                    await self.keyboard_press('ArrowRight', delay=ALBUM_NAVIGATION_DELAY)
                
                # Get album info
                album_info = await self.get_album_info()
                console.print(f"[green]Collecting album: {album_info.title}[/green]")
                
                # Insert album into database
                album_id = insert_or_update_album(album_info)
                albums_processed.append(album_info)

                if prev_album and prev_album.href == album_info.href:
                    console.print(f"[yellow]All albums collected[/yellow]")
                    break
                prev_album = album_info
                
                # Small delay between albums
                await asyncio.sleep(0.3)

            except Exception as e:
                error_msg = f"Error collecting album {album_position}: {e}"
                logger.error(error_msg)
                # Continue with next album instead of breaking
                continue
        
        return albums_processed

    async def scrape_albums_from_db(self, max_albums: int = None, start_album: int = 1) -> ProcessingResult:
        """Process images from albums stored in the database."""
        await self.setup_browser()
        
        albums_processed = []
        errors = []
        
        # Initialize browser context here to keep it alive during scraping
        async with async_playwright() as p:
            try:
                # Add storage clearing arguments by default
                storage_args = [
                    '--clear-browsing-data',
                    '--clear-browsing-data-on-exit',
                    '--disable-session-crashed-bubble',
                    '--disable-infobars',
                    '--disable-restore-session-state'
                ]
                all_args = STEALTH_ARGS + storage_args
                
                self.context = await p.chromium.launch_persistent_context(
                    user_data_dir=USER_DATA_DIR,
                    headless=False,
                    executable_path=BRAVE_EXECUTABLE,
                    args=all_args,
                    ignore_default_args=["--enable-automation"],
                    viewport={"width": 1280, "height": 720},
                    slow_mo=40,
                )
                
                self.page = self.context.pages[0] if self.context.pages else await self.context.new_page()
                
                # Set up stealth mode
                await self.page.add_init_script(STEALTH_INIT_SCRIPT)
                
                # Navigate to Google Photos
                await self.page.goto("https://photos.google.com")
                await self.page.wait_for_load_state("domcontentloaded")
                
                # Wait for login if needed
                if self.login:
                    console.print("[yellow]Waiting for login... Please log in to Google Photos in the browser.[/yellow]")
                    console.print("[yellow]Press Enter in the console once you're logged in.[/yellow]")
                    input()
                
                # Get albums from database
                offset = start_album - 1  # Convert to 0-based offset
                albums = get_albums_from_db(limit=max_albums, offset=offset)
                
                if not albums:
                    if self.albums_only:
                        console.print("[yellow]No albums found in database. Collecting albums now...[/yellow]")
                        # Collect albums from UI
                        collected_albums = await self.collect_albums(max_albums=max_albums, start_album=start_album)
                        if collected_albums:
                            console.print(f"[green]Successfully collected {len(collected_albums)} albums[/green]")
                            # In albums-only mode, we're done after collecting
                            return ProcessingResult(
                                total_albums=len(collected_albums),
                                total_pictures=0,
                                albums_processed=collected_albums,
                                errors=[]
                            )
                        else:
                            console.print("[red]No albums were collected[/red]")
                            return ProcessingResult(
                                total_albums=0,
                                total_pictures=0,
                                albums_processed=[],
                                errors=[]
                            )
                    else:
                        console.print("[yellow]No albums found in database. Run with --albums-only first to collect albums.[/yellow]")
                        return ProcessingResult(
                            total_albums=0,
                            total_pictures=0,
                            albums_processed=[],
                            errors=[]
                        )
                
                console.print(f"[green]Found {len(albums)} albums to process from database[/green]")
                
                # Process each album
                for i, (album_id, album_gphoto_url, album_gphoto_title, album_items) in enumerate(albums):
                    try:
                        console.print(f"[blue]Processing album {i + 1}/{len(albums)}: {album_gphoto_title}[/blue]")
                        
                        # Process the album from database
                        processed_album = await self.process_album_from_db(
                            album_id=album_id,
                            album_gphoto_url=album_gphoto_url,
                            album_gphoto_title=album_gphoto_title,
                            album_items=album_items
                        )
                        
                        albums_processed.append(processed_album)
                        
                    except Exception as e:
                        error_msg = f"Error processing album {album_gphoto_title}: {e}"
                        logger.error(error_msg)
                        errors.append(error_msg)
                        # Save error to database
                        try:
                            insert_error(error_msg, album_id)
                        except Exception as db_error:
                            logger.error(f"Error saving error to database: {db_error}")
                
                # Print summary
                self._print_summary(albums_processed, errors)
                
                return ProcessingResult(
                    total_albums=len(albums),
                    total_pictures=sum(len(album.pictures) for album in albums_processed),
                    albums_processed=albums_processed,
                    errors=errors
                )
                
            finally:
                if self.context:
                    try:
                        # Close all pages first
                        for page in self.context.pages:
                            try:
                                await page.close()
                            except Exception as e:
                                logger.debug(f"Error closing page: {e}")
                        
                        # Close the context (this should also close the browser for persistent context)
                        await self.context.close()
                        logger.debug("Browser context closed successfully")
                        
                    except Exception as e:
                        logger.error(f"Error closing browser context: {e}")
                        insert_error(f"Error closing browser context: {e}")

    def _print_summary(self, albums: List[AlbumInfo], errors: List[str]) -> None:
        """Print processing summary."""
        console.print("\n[bold green]=== Processing Summary ===[/bold green]")
        console.print(f"[green]Total albums processed: {len(albums)}[/green]")
        console.print(f"[green]Total pictures extracted: {sum(len(album.pictures) for album in albums)}[/green]")

        for album in albums:
            console.print(f"  [blue]{album.title}:[/blue] {len(album.pictures)} pictures")

        if errors:
            console.print(f"\n[red]Errors encountered: {len(errors)}[/red]")
            for error in errors:
                console.print(f"  [red]• {error}[/red]")

        console.print("[blue]You can now close the browser or press Enter to exit...[/blue]")
        input()

    def get_database_stats(self) -> Dict[str, Any]:
        """Get database statistics."""
        session = get_db_session()
        try:
            stats = {}
            
            # Get album counts
            stats['total_albums'] = session.query(Album).count()
            
            # Get photo counts
            stats['total_photos'] = session.query(Photo).count()
            
            # Get user counts
            stats['total_users'] = session.query(User).count()
            
            # Get error counts
            stats['total_errors'] = session.query(Error).count()
            
            # Get album-user relationship counts
            stats['total_album_users'] = session.query(AlbumUser).count()
            
            # Get photos per album with processed items
            photos_per_album = session.query(
                Album.gphoto_title,
                Album.items,
                Album.processed_items,
                func.count(Photo.id).label('photo_count')
            ).outerjoin(Photo).group_by(Album.id, Album.gphoto_title, Album.items, Album.processed_items).order_by(
                func.count(Photo.id).desc()
            ).all()
            stats['photos_per_album'] = [(album_gphoto_title, total_items, processed_items, photo_count) for album_gphoto_title, total_items, processed_items, photo_count in photos_per_album]
            
            # Get users per album
            users_per_album = session.query(
                Album.gphoto_title,
                func.count(User.id).label('user_count')
            ).join(Album.users).group_by(Album.id, Album.gphoto_title).order_by(
                func.count(User.id).desc()
            ).all()
            stats['users_per_album'] = [(album_gphoto_title, user_count) for album_gphoto_title, user_count in users_per_album]
            
            return stats
        finally:
            session.close()
    
    def print_database_summary(self) -> None:
        """Print a summary of database contents."""
        stats = self.get_database_stats()
        
        console.print("\n[bold green]=== Database Summary ===[/bold green]")
        console.print(f"[green]Total albums: {stats['total_albums']}[/green]")
        console.print(f"[green]Total photos: {stats['total_photos']}[/green]")
        console.print(f"[green]Total users: {stats['total_users']}[/green]")
        console.print(f"[green]Total errors: {stats['total_errors']}[/green]")
        console.print(f"[green]Total album-user relationships: {stats['total_album_users']}[/green]")
        
        console.print("\n[bold blue]=== Photos per Album ===[/bold blue]")
        for album_data in stats['photos_per_album'][:10]:  # Show top 10
            if len(album_data) == 4:
                album_gphoto_title, total_items, processed_items, photo_count = album_data
                # Format processed items as x/y photos
                processed_str = f"{processed_items or 0}/{total_items or '?'}" if total_items else f"{processed_items or 0}"
                console.print(f"  [blue]{album_gphoto_title}:[/blue] {processed_str} photos ({photo_count} in database)")
            else:
                # Fallback for old format
                album_gphoto_title, photo_count = album_data
                console.print(f"  [blue]{album_gphoto_title}:[/blue] {photo_count} photos")
        
        if len(stats['photos_per_album']) > 10:
            console.print(f"  ... and {len(stats['photos_per_album']) - 10} more albums")
        
        console.print("\n[bold blue]=== Users per Album ===[/bold blue]")
        for album_gphoto_title, user_count in stats['users_per_album'][:10]:  # Show top 10
            console.print(f"  [blue]{album_gphoto_title}:[/blue] {user_count} users")
        
        if len(stats['users_per_album']) > 10:
            console.print(f"  ... and {len(stats['users_per_album']) - 10} more albums")

@click.command()
@click.option('--login', help='Login is needed, if set it waits until you are logged in.')
@click.option('-m', '--max-albums', default=MAX_ALBUMS, help='Maximum number of albums to process')
@click.option('-s', '--start-album', default=1, help='Start processing from this album position (1-based)')
@click.option('-f', '--start-album-fresh', is_flag=True, help='Start processing from the beginning, ignoring existing albums')
@click.option('-a', '--albums-only', is_flag=True, help='Only add albums to database without processing photos')
@click.option('-p', '--process-images', is_flag=True, help='Process images from albums in database (requires albums to be collected first)')
@click.option('-d', '--db-path', default=DATABASE_PATH, help='Path to the SQLite database file')
@click.option('-c', '--chrome-bin', default=BRAVE_EXECUTABLE, help='Path to Chrome/Brave binary')
@click.option('-r', '--reset-db', is_flag=True, help='Delete and recreate the database')
@click.option('-i', '--init-db-only', is_flag=True, help='Only initialize the database and exit')
@click.option('-t', '--show-stats', is_flag=True, help='Show database statistics and exit')
@click.option('--log-level', type=click.Choice(['debug', 'info', 'warning', 'error']), default='warning', help='Set the logging level (default: WARNING)')
def main(login: bool, max_albums: int, start_album: int, start_album_fresh: bool, albums_only: bool, process_images: bool, db_path: str, chrome_bin: str, reset_db: bool, init_db_only: bool, show_stats: bool, log_level: str):
    """Main entry point."""
    max_albums = max_albums if max_albums > 0 else 100000
    if start_album < 1:
        raise click.UsageError("Start album must be 1 or higher (--start-album)")

    # Update global database path and chrome binary
    global DATABASE_PATH, BRAVE_EXECUTABLE
    DATABASE_PATH = db_path
    BRAVE_EXECUTABLE = chrome_bin
    
    # Configure logging level with enhanced colors
    logger.remove()  # Remove default handler
    logger.add(
        lambda msg: print(msg, end=""),
        level=log_level.upper(),
        #format="<green>{time:HH:mm:ss}</green> <blue>|</blue> <level>{level: <8}</level> <blue>|</blue> <magenta>{name}</magenta><blue>:</blue><cyan>{function}</cyan><blue>:</blue><yellow>{line}</yellow> <blue>-</blue> <level>{message}</level>",
        format="<green>{time:HH:mm:ss}</green> <level>{level: <8}</level><level>{message}</level>",
        colorize=True
    )
    console.print(f"[blue]Logging level set to: {log_level}[/blue]")
    
    # Handle database reset
    if reset_db:
        db_file = Path(DATABASE_PATH)
        if db_file.exists():
            console.print(f"[yellow]Deleting existing database: {DATABASE_PATH}[/yellow]")
            db_file.unlink()
            console.print("[green]Database deleted successfully[/green]")
        else:
            console.print(f"[blue]Database file not found: {DATABASE_PATH}[/blue]")
    
    # Initialize database
    init_database()
    
    if init_db_only:
        console.print("[green]Database initialized successfully. Exiting.[/green]")
        return
    
    # Determine skip_existing logic
    skip_existing = not reset_db
    
    if show_stats:
        scraper = GooglePhotosScraper(login=login,max_albums=max_albums, skip_existing=skip_existing)
        scraper.print_database_summary()
        return
    
    # Run the scraper
    async def run_scraper():
        scraper = GooglePhotosScraper(login=login, max_albums=max_albums, start_album=start_album, album_fresh=start_album_fresh, skip_existing=skip_existing, albums_only=albums_only)
        
        # Process images from albums in database
        if albums_only:
            console.print("[green]Albums-only mode: Collecting albums only (no image processing)...[/green]")
        else:
            console.print("[green]Processing images from albums in database...[/green]")
        result = await scraper.scrape_albums_from_db(max_albums=max_albums, start_album=start_album)
        
        # Print database summary
        scraper.print_database_summary()
    
    asyncio.run(run_scraper())

if __name__ == "__main__":
    main()
