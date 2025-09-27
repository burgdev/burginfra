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
# ]
# ///

# Skip Playwright browser download since we use our own browser
import os
os.environ['PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD'] = 'true'

import asyncio
import time
import logging
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

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

console = Console()

# Configuration constants
USER_DATA_DIR = "./brave_playwright_profile2"
BRAVE_EXECUTABLE = "/usr/bin/brave-browser"
DEFAULT_TIMEOUT = 10000
INFO_PANEL_TIMEOUT = 2000
ALBUM_NAVIGATION_DELAY = 1.5
IMAGE_NAVIGATION_DELAY = 0.05
DUPLICATE_THRESHOLD = 10
DUPLICATE_LOG_THRESHOLD = 4
MAX_ALBUMS = 3
DATABASE_PATH = "photos.db"

# SQLAlchemy setup
Base = declarative_base()
engine = create_engine(f"sqlite:///{DATABASE_PATH}")
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

class Album(Base):
    """SQLAlchemy model for albums."""
    __tablename__ = "albums"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    title = Column(String, unique=True, nullable=False)
    items = Column(Integer)
    processed_items = Column(Integer, default=0)
    shared = Column(Boolean, default=False)
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())
    
    # Relationships
    photos = relationship("Photo", back_populates="album", cascade="all, delete-orphan")
    errors = relationship("Error", back_populates="album")
    users = relationship("User", secondary="album_users", back_populates="albums")
    
    def __repr__(self):
        return f"<Album(title='{self.title}', items={self.items}, shared={self.shared})>"

class User(Base):
    """SQLAlchemy model for users."""
    __tablename__ = "users"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String, unique=True, nullable=False)
    email = Column(String, nullable=True)  # Email field, nullable for manual filling later
    created_at = Column(DateTime, default=func.now())
    
    # Relationships
    albums = relationship("Album", secondary="album_users", back_populates="users")
    
    def __repr__(self):
        return f"<User(name='{self.name}', email='{self.email}')>"

class Photo(Base):
    """SQLAlchemy model for photos."""
    __tablename__ = "photos"
    
    id = Column(Integer, primary_key=True, autoincrement=True)
    filename = Column(String, nullable=False)
    date_taken = Column(DateTime)
    album_id = Column(Integer, ForeignKey("albums.id", ondelete="CASCADE"))
    created_at = Column(DateTime, default=func.now())
    
    # Relationships
    album = relationship("Album", back_populates="photos")
    
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
    "--no-sandbox",
    "--disable-infobars",
    "--disable-extensions",
    "--start-maximized",
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
        
        # Check if the email column exists in users table
        try:
            session.execute(text("SELECT email FROM users LIMIT 1"))
        except Exception:
            # Column doesn't exist, add it
            console.print("[yellow]Adding email column to users table...[/yellow]")
            session.execute(text("ALTER TABLE users ADD COLUMN email VARCHAR(255)"))
            session.commit()
            console.print("[green]Added email column to users table[/green]")
        finally:
            session.close()
            
        # Create photos_with_album view
        create_photos_with_album_view()
            
        console.print("[green]Database initialized successfully[/green]")
    except Exception as e:
        console.print(f"[red]Error initializing database: {e}[/red]")
        raise e

def insert_or_update_album(album_info: "AlbumInfo") -> int:
    """Insert or update an album and return its ID."""
    session = get_db_session()
    try:
        # Check if album exists
        existing_album = session.query(Album).filter_by(title=album_info.title).first()
        
        if existing_album:
            # Update existing album
            existing_album.items = album_info.items
            existing_album.shared = album_info.shared
            # Don't reset processed_items when updating album info
            existing_album.updated_at = func.now()
            album_id = existing_album.id
        else:
            # Create new album
            new_album = Album(
                title=album_info.title,
                items=album_info.items,
                processed_items=0,  # Start with 0 processed items
                shared=album_info.shared
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

def insert_or_update_user(name: str) -> int:
    """Insert or update a user and return their ID."""
    session = get_db_session()
    try:
        # Check if user exists
        existing_user = session.query(User).filter_by(name=name).first()
        
        if existing_user:
            user_id = existing_user.id
        else:
            # Create new user
            new_user = User(name=name)
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

def insert_photo(filename: str, date_taken: Optional[datetime], album_id: int) -> Optional[int]:
    """Insert a photo and return its ID. Returns None if photo already exists."""
    session = get_db_session()
    try:
        # Check if photo already exists
        existing_photo = session.query(Photo).filter_by(
            filename=filename, 
            album_id=album_id
        ).first()
        
        if existing_photo:
            return None
        
        # Create new photo
        new_photo = Photo(
            filename=filename,
            date_taken=date_taken,
            album_id=album_id
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

def album_exists(title: str) -> bool:
    """Check if an album with the given title exists."""
    session = get_db_session()
    try:
        album = session.query(Album).filter_by(title=title).first()
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
        # Users are aggregated into a JSON array of objects with name and email to have one entry per photo
        create_view_sql = """
        CREATE VIEW photos_with_album AS
        SELECT 
            p.id as photo_id,
            p.filename,
            p.date_taken,
            p.created_at as photo_created_at,
            a.id as album_id,
            a.title as album_title,
            a.items as album_items,
            a.processed_items as album_processed_items,
            a.shared as album_shared,
            json_group_array(
                json_object('name', u.name, 'email', u.email)
            ) FILTER (WHERE u.name IS NOT NULL) as users
        FROM photos p
        LEFT JOIN albums a ON p.album_id = a.id
        LEFT JOIN album_users au ON a.id = au.album_id
        LEFT JOIN users u ON au.user_id = u.id
        GROUP BY p.id, p.filename, p.date_taken, p.created_at, 
                 a.id, a.title, a.items, a.processed_items, a.shared
        ORDER BY p.album_id, p.date_taken DESC
        """
        
        session.execute(text(create_view_sql))
        session.commit()
        console.print("[green]Created photos_with_album view successfully[/green]")
    except Exception as e:
        session.rollback()
        console.print(f"[red]Error creating photos_with_album view: {e}[/red]")
        raise e
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

@dataclass
class ProcessingResult:
    """Data class for overall processing results."""
    total_albums: int
    total_pictures: int
    albums_processed: List[AlbumInfo]
    errors: List[str]

class GooglePhotosScraper:
    """Main scraper class for Google Photos."""

    def __init__(self, max_albums: int = 5, start_album: int = 0, skip_existing: bool = False, albums_only: bool = False):
        self.max_albums = max_albums
        self.start_album = start_album
        self.skip_existing = skip_existing
        self.albums_only = albums_only
        self.context = None
        self.page = None

    async def setup_browser(self) -> None:
        """Initialize and setup the browser context."""
        Path(USER_DATA_DIR).mkdir(exist_ok=True)
        # Note: Browser context is now managed in scrape_albums()
        # This method just prepares the configuration
        pass

    async def get_album_info(self) -> AlbumInfo:
        """Extract album information from the current selection."""
        try:
            # Get the currently selected album element
            selected_element = await self.page.evaluate_handle('document.activeElement')
            children = await selected_element.query_selector_all("div")

            if len(children) < 2:
                raise ValueError("Could not find album information elements")

            album_title, description = (await children[1].inner_text()).split("\n")
            items = int(description.split(" ")[0])
            shared = "shared" in description.lower()

            console.print(f"[blue]Album Title:[/blue] {album_title}")
            console.print(f"[blue]Items:[/blue] {items}")
            console.print(f"[blue]Shared:[/blue] {shared}")

            return AlbumInfo(
                title=album_title,
                items=items,
                shared="shared" in description.lower(),
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
            filename = await self._get_text_safely('div[aria-label*="Filename"]', timeout=INFO_PANEL_TIMEOUT)
            if not filename:
                return None

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
            logger.error(f"Error getting picture info: {e}")
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
                    console.print(f"[yellow]Multiple visible elements found for selector: {selector}[/yellow]")
                elif len(visible_elements) == 1:
                    return visible_elements[0]
            except PlaywrightTimeoutError:
                console.print(f"[yellow]Timed out waiting for element: {selector}[/yellow]")
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

    async def process_album(self, album_info: AlbumInfo) -> AlbumInfo:
        """Process all pictures in an album and save to database."""
        console.print(f"[green]Processing album: {album_info.title}[/green]")

        # Insert or update album in database first to get album_id
        album_id = insert_or_update_album(album_info)
        
        # Check if album should be skipped
        if self.skip_existing and not self.albums_only:
            if is_album_fully_processed(album_id):
                console.print(f"[yellow]Skipping fully processed album: {album_info.title}[/yellow]")
                return album_info
            elif album_exists(album_info.title):
                existing_count = get_album_photos_count(album_id)
                console.print(f"[blue]Continuing partially processed album: {album_info.title} (has {existing_count}/{album_info.items} photos)[/blue]")
        
        # If albums_only mode, just add the album and return
        if self.albums_only:
            console.print(f"[blue]Albums-only mode: Added album {album_info.title} to database[/blue]")
            await asyncio.sleep(0.3)
            return album_info

        # Open the album
        await self.page.keyboard.press('Enter')
        await asyncio.sleep(ALBUM_NAVIGATION_DELAY)
        await self.page.keyboard.press('Enter')
        await asyncio.sleep(0.3)

        pictures = []
        last_filename = None
        duplicate_count = 0
        processed_users = set()
        
        # Get current photo count to continue from where we left off
        current_photo_count = get_album_photos_count(album_id)

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console
        ) as progress:
            task = progress.add_task(
                f"Processing {album_info.title}...",
                total=album_info.items,
                completed=current_photo_count
            )

            photo_index = 0
            while current_photo_count < album_info.items:
                if photo_index <= current_photo_count:
                    # already in DB
                    await self.page.keyboard.press('ArrowRight')
                    await asyncio.sleep(IMAGE_NAVIGATION_DELAY)
                    photo_index += 1
                    continue
                    
                try:
                    picture_info = await self.get_picture_info(album_info.title)

                    if not picture_info:
                        console.print("[red]Could not extract info for current image[/red]")
                        break

                    # Check for duplicates to detect end of album
                    if picture_info.filename == last_filename and picture_info.filename != "N/A":
                        duplicate_count += 1
                        if duplicate_count >= DUPLICATE_LOG_THRESHOLD:
                            await asyncio.sleep(1)
                            console.print(f"[pink]Duplicate filename detected: {picture_info.filename} ({duplicate_count})[/pink]")

                        if duplicate_count >= DUPLICATE_THRESHOLD:
                            console.print("[yellow]Reached end of album (duplicate threshold met)[/yellow]")
                            break

                        await asyncio.sleep(0.15)
                        continue
                        

                    # New picture found
                    last_filename = picture_info.filename
                    pictures.append(picture_info)
                    duplicate_count = 0

                    # Save to database
                    try:
                        # Insert photo
                        photo_id = insert_photo(
                            picture_info.filename,
                            picture_info.date,
                            album_id
                        )
                        
                        # Only count as processed if it was actually inserted (not duplicate)
                        if photo_id is not None:
                            photo_index += 1
                            # Update processed items count
                            # new_processed_count = current_photo_count + len(pictures) + 1
                            current_photo_count += 1
                            update_album_processed_items(album_id, current_photo_count)
                        
                        # Handle user information
                        if picture_info.shared_by and picture_info.shared_by != "N/A":
                            user_id = insert_or_update_user(picture_info.shared_by)
                            link_user_to_album(album_id, user_id)
                            processed_users.add(picture_info.shared_by)
                            
                    except Exception as e:
                        logger.error(f"Error saving picture to database: {e}")
                        insert_error(f"Error saving picture {picture_info.filename}: {e}", album_id)

                    # Display progress
                    #actual_processed = current_photo_count + len(pictures) + (1 if photo_id is not None else 0)
                    progress.update(task, advance=1 if photo_id is not None else 0, description=
                        f"[green]{current_photo_count}/{album_info.items} - {picture_info.filename}[/green]")

                    # Navigate to next image
                    #console.print(f"[green]Processing {picture_info.filename}, clicking next[/green]")
                    await self.page.keyboard.press('ArrowRight')
                    await asyncio.sleep(IMAGE_NAVIGATION_DELAY)

                except Exception as e:
                    logger.error(f"Error processing picture: {e}")
                    insert_error(f"Error processing picture in album {album_info.title}: {e}", album_id)
                    break

        # Return to album view
        await self.page.keyboard.press('Escape')
        await asyncio.sleep(0.5)
        await self.page.keyboard.press('Escape')
        await asyncio.sleep(1)

        album_info.pictures = pictures
        console.print(f"[green]Processed {len(pictures)} pictures from {album_info.title}[/green]")
        if processed_users:
            console.print(f"[blue]Associated users: {', '.join(processed_users)}[/blue]")
        return album_info

    async def navigate_to_next_album(self, current_index: int) -> None:
        """Navigate to the next album using arrow keys."""
        for _ in range(current_index + 1):
            await self.page.keyboard.press('ArrowRight')
        await asyncio.sleep(0.2)

    async def scrape_albums(self) -> ProcessingResult:
        """Main scraping workflow."""
        await self.setup_browser()

        # Initialize browser context here to keep it alive during scraping
        async with async_playwright() as p:
            self.context = await p.chromium.launch_persistent_context(
                user_data_dir=USER_DATA_DIR,
                headless=False,
                executable_path=BRAVE_EXECUTABLE,
                args=STEALTH_ARGS,
                ignore_default_args=["--enable-automation"],
                viewport={"width": 1280, "height": 720},
                slow_mo=40,
            )
            await self.context.add_init_script(STEALTH_INIT_SCRIPT)

            self.page = self.context.pages[0] if self.context.pages else await self.context.new_page()
            self.page.set_default_timeout(DEFAULT_TIMEOUT)

            try:
                # Navigate to Google Photos albums
                await self.page.goto("https://photos.google.com/albums")
                click.confirm("Press Enter when albums are ready...", default=True)

                albums_processed = []
                errors = []

                console.print(f"[blue]Starting to process {self.max_albums} albums from index {self.start_album}...[/blue]")
                if self.skip_existing:
                    console.print("[yellow]Skip existing albums mode enabled[/yellow]")
                if self.albums_only:
                    console.print("[yellow]Albums-only mode enabled - will not open albums or process photos[/yellow]")
                
                # Navigate to the first album to process
                if self.start_album > 0:
                    console.print(f"[yellow]Navigating to album index {self.start_album}...[/yellow]")
                    await self.navigate_to_next_album(self.start_album - 1)
                
                for album_index in range(self.start_album, self.start_album + self.max_albums):
                    try:
                        # Navigate to next album (only one step from current position)
                        if album_index > self.start_album:
                            await self.page.keyboard.press('ArrowRight')
                            await asyncio.sleep(0.2)

                        # Get album info
                        album_info = await self.get_album_info()

                        # Process album
                        processed_album = await self.process_album(album_info)
                        albums_processed.append(processed_album)
                        
                        # In albums_only mode, return to album view after processing each album
                        if self.albums_only:
                            await self.page.keyboard.press('Escape')
                            await asyncio.sleep(0.5)

                    except Exception as e:
                        error_msg = f"Error processing album {album_index + 1}: {e}"
                        logger.error(error_msg)
                        errors.append(error_msg)
                        # Save error to database
                        try:
                            insert_error(error_msg)
                        except Exception as db_error:
                            logger.error(f"Error saving error to database: {db_error}")

                # Print summary
                self._print_summary(albums_processed, errors)

                return ProcessingResult(
                    total_albums=self.max_albums,
                    total_pictures=sum(len(album.pictures) for album in albums_processed),
                    albums_processed=albums_processed,
                    errors=errors
                )

            finally:
                if self.context:
                    try:
                        await self.context.close()
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
                Album.title,
                Album.items,
                Album.processed_items,
                func.count(Photo.id).label('photo_count')
            ).outerjoin(Photo).group_by(Album.id, Album.title, Album.items, Album.processed_items).order_by(
                func.count(Photo.id).desc()
            ).all()
            stats['photos_per_album'] = [(album_title, total_items, processed_items, photo_count) for album_title, total_items, processed_items, photo_count in photos_per_album]
            
            # Get users per album
            users_per_album = session.query(
                Album.title,
                func.count(User.id).label('user_count')
            ).join(Album.users).group_by(Album.id, Album.title).order_by(
                func.count(User.id).desc()
            ).all()
            stats['users_per_album'] = [(album_title, user_count) for album_title, user_count in users_per_album]
            
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
                album_title, total_items, processed_items, photo_count = album_data
                # Format processed items as x/y photos
                processed_str = f"{processed_items or 0}/{total_items or '?'}" if total_items else f"{processed_items or 0}"
                console.print(f"  [blue]{album_title}:[/blue] {processed_str} photos ({photo_count} in database)")
            else:
                # Fallback for old format
                album_title, photo_count = album_data
                console.print(f"  [blue]{album_title}:[/blue] {photo_count} photos")
        
        if len(stats['photos_per_album']) > 10:
            console.print(f"  ... and {len(stats['photos_per_album']) - 10} more albums")
        
        console.print("\n[bold blue]=== Users per Album ===[/bold blue]")
        for album_title, user_count in stats['users_per_album'][:10]:  # Show top 10
            console.print(f"  [blue]{album_title}:[/blue] {user_count} users")
        
        if len(stats['users_per_album']) > 10:
            console.print(f"  ... and {len(stats['users_per_album']) - 10} more albums")

@click.command()
@click.option('-m', '--max-albums', default=MAX_ALBUMS, help='Maximum number of albums to process')
@click.option('-s', '--start-album', default=0, help='Start processing from this album index (0-based)')
@click.option('-f', '--start-album-fresh', is_flag=True, help='Start processing from the beginning, ignoring existing albums')
@click.option('-n', '--no-skip-existing', is_flag=True, help='Process all albums, including existing ones')
@click.option('-a', '--albums-only', is_flag=True, help='Only add albums to database without processing photos')
@click.option('-d', '--db-path', default=DATABASE_PATH, help='Path to the SQLite database file')
@click.option('-c', '--chrome-bin', default=BRAVE_EXECUTABLE, help='Path to Chrome/Brave binary')
@click.option('-r', '--reset-db', is_flag=True, help='Delete and recreate the database')
@click.option('-i', '--init-db-only', is_flag=True, help='Only initialize the database and exit')
@click.option('-t', '--show-stats', is_flag=True, help='Show database statistics and exit')
def main(max_albums: int, start_album: int, start_album_fresh: bool, no_skip_existing: bool, albums_only: bool, db_path: str, chrome_bin: str, reset_db: bool, init_db_only: bool, show_stats: bool):
    """Main entry point."""
    # Update global database path and chrome binary
    global DATABASE_PATH, BRAVE_EXECUTABLE
    DATABASE_PATH = db_path
    BRAVE_EXECUTABLE = chrome_bin
    
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
    skip_existing = not no_skip_existing and not start_album_fresh
    
    if start_album_fresh:
        start_album = 0
        console.print("[yellow]Starting fresh from album 0, ignoring existing albums[/yellow]")
    
    if show_stats:
        scraper = GooglePhotosScraper(max_albums=max_albums, skip_existing=skip_existing)
        scraper.print_database_summary()
        return
    
    # Run the scraper
    async def run_scraper():
        scraper = GooglePhotosScraper(max_albums=max_albums, start_album=start_album, skip_existing=skip_existing, albums_only=albums_only)
        result = await scraper.scrape_albums()
        
        # Print database summary
        scraper.print_database_summary()
    
    asyncio.run(run_scraper())

if __name__ == "__main__":
    main()
