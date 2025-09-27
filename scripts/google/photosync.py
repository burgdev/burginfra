#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "playwright",
#   "rich",
#   "python-dateutil",
#   "click",
#   "pydantic",
# ]
# ///

# Skip Playwright browser download since we use our own browser
import os
os.environ['PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD'] = 'true'

import asyncio
import time
import logging
import sqlite3
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

def get_db_connection() -> sqlite3.Connection:
    """Get a database connection."""
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_database() -> None:
    """Initialize the database with all required tables."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Create albums table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS albums (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT UNIQUE NOT NULL,
            items INTEGER,
            shared BOOLEAN,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Create users table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Create photos table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            date_taken TIMESTAMP,
            album_id INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (album_id) REFERENCES albums (id) ON DELETE CASCADE
        )
    """)
    
    # Create errors table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS errors (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            error_message TEXT NOT NULL,
            album_id INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (album_id) REFERENCES albums (id) ON DELETE SET NULL
        )
    """)
    
    # Create album_users table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS album_users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            album_id INTEGER,
            user_id INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (album_id) REFERENCES albums (id) ON DELETE CASCADE,
            FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
            UNIQUE(album_id, user_id)
        )
    """)
    
    conn.commit()
    conn.close()
    console.print("[green]Database initialized successfully[/green]")

def insert_or_update_album(album_info: "AlbumInfo") -> int:
    """Insert or update an album and return its ID."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        INSERT OR REPLACE INTO albums (title, items, shared, updated_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
    """, (album_info.title, album_info.items, album_info.shared))
    
    album_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return album_id

def insert_or_update_user(name: str) -> int:
    """Insert or update a user and return their ID."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        INSERT OR IGNORE INTO users (name)
        VALUES (?)
    """, (name,))
    
    if cursor.rowcount == 0:
        # User already exists, get their ID
        cursor.execute("SELECT id FROM users WHERE name = ?", (name,))
        user_id = cursor.fetchone()[0]
    else:
        user_id = cursor.lastrowid
    
    conn.commit()
    conn.close()
    return user_id

def insert_photo(filename: str, date_taken: Optional[datetime], album_id: int) -> int:
    """Insert a photo and return its ID."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        INSERT OR IGNORE INTO photos (filename, date_taken, album_id)
        VALUES (?, ?, ?)
    """, (filename, date_taken, album_id))
    
    photo_id = cursor.lastrowid if cursor.rowcount > 0 else None
    conn.commit()
    conn.close()
    return photo_id

def insert_error(error_message: str, album_id: Optional[int] = None) -> int:
    """Insert an error and return its ID."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        INSERT INTO errors (error_message, album_id)
        VALUES (?, ?)
    """, (error_message, album_id))
    
    error_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return error_id

def link_user_to_album(album_id: int, user_id: int) -> None:
    """Link a user to an album."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        INSERT OR IGNORE INTO album_users (album_id, user_id)
        VALUES (?, ?)
    """, (album_id, user_id))
    
    conn.commit()
    conn.close()

def album_exists(title: str) -> bool:
    """Check if an album with the given title exists."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM albums WHERE title = ?", (title,))
    exists = cursor.fetchone()[0] > 0
    
    conn.close()
    return exists

def get_album_photos_count(album_id: int) -> int:
    """Get the number of photos for a given album."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM photos WHERE album_id = ?", (album_id,))
    count = cursor.fetchone()[0]
    
    conn.close()
    return count

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

    def __init__(self, max_albums: int = 5, skip_existing: bool = False):
        self.max_albums = max_albums
        self.skip_existing = skip_existing
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

        # Check if album should be skipped
        if self.skip_existing and album_exists(album_info.title):
            existing_count = get_album_photos_count(insert_or_update_album(album_info))
            console.print(f"[yellow]Skipping existing album: {album_info.title} (already has {existing_count} photos)[/yellow]")
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
        
        # Insert or update album in database
        album_id = insert_or_update_album(album_info)

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console
        ) as progress:
            task = progress.add_task(
                f"Processing {album_info.title}...",
                total=album_info.items
            )

            while len(pictures) < album_info.items:
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
                        
                        # Handle user information
                        if picture_info.shared_by and picture_info.shared_by != "N/A":
                            user_id = insert_or_update_user(picture_info.shared_by)
                            link_user_to_album(album_id, user_id)
                            processed_users.add(picture_info.shared_by)
                            
                    except Exception as e:
                        logger.error(f"Error saving picture to database: {e}")
                        insert_error(f"Error saving picture {picture_info.filename}: {e}", album_id)

                    # Display progress
                    progress.update(task, advance=1, description=
                        f"[green]{len(pictures)}/{album_info.items} - {picture_info.filename}[/green]")

                    # Navigate to next image
                    console.print(f"[green]Processing {picture_info.filename}, clicking next[/green]")
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

                console.print(f"[blue]Starting to process {self.max_albums} albums...[/blue]")
                if self.skip_existing:
                    console.print("[yellow]Skip existing albums mode enabled[/yellow]")

                for album_index in range(self.max_albums):
                    try:
                        # Navigate to album
                        await self.navigate_to_next_album(album_index)

                        # Get album info
                        album_info = await self.get_album_info()

                        # Process album
                        processed_album = await self.process_album(album_info)
                        albums_processed.append(processed_album)

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
        conn = get_db_connection()
        cursor = conn.cursor()
        
        stats = {}
        
        # Get album counts
        cursor.execute("SELECT COUNT(*) FROM albums")
        stats['total_albums'] = cursor.fetchone()[0]
        
        # Get photo counts
        cursor.execute("SELECT COUNT(*) FROM photos")
        stats['total_photos'] = cursor.fetchone()[0]
        
        # Get user counts
        cursor.execute("SELECT COUNT(*) FROM users")
        stats['total_users'] = cursor.fetchone()[0]
        
        # Get error counts
        cursor.execute("SELECT COUNT(*) FROM errors")
        stats['total_errors'] = cursor.fetchone()[0]
        
        # Get album-user relationship counts
        cursor.execute("SELECT COUNT(*) FROM album_users")
        stats['total_album_users'] = cursor.fetchone()[0]
        
        # Get photos per album
        cursor.execute("""
            SELECT a.title, COUNT(p.id) as photo_count
            FROM albums a
            LEFT JOIN photos p ON a.id = p.album_id
            GROUP BY a.id, a.title
            ORDER BY photo_count DESC
        """)
        stats['photos_per_album'] = cursor.fetchall()
        
        # Get users per album
        cursor.execute("""
            SELECT a.title, COUNT(au.user_id) as user_count
            FROM albums a
            LEFT JOIN album_users au ON a.id = au.album_id
            GROUP BY a.id, a.title
            ORDER BY user_count DESC
        """)
        stats['users_per_album'] = cursor.fetchall()
        
        conn.close()
        return stats
    
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
        for album_title, photo_count in stats['photos_per_album'][:10]:  # Show top 10
            console.print(f"  [blue]{album_title}:[/blue] {photo_count} photos")
        
        if len(stats['photos_per_album']) > 10:
            console.print(f"  ... and {len(stats['photos_per_album']) - 10} more albums")
        
        console.print("\n[bold blue]=== Users per Album ===[/bold blue]")
        for album_title, user_count in stats['users_per_album'][:10]:  # Show top 10
            console.print(f"  [blue]{album_title}:[/blue] {user_count} users")
        
        if len(stats['users_per_album']) > 10:
            console.print(f"  ... and {len(stats['users_per_album']) - 10} more albums")

@click.command()
@click.option('--max-albums', default=MAX_ALBUMS, help='Maximum number of albums to process')
@click.option('--skip-existing', is_flag=True, help='Skip albums that already exist in the database')
@click.option('--db-path', default=DATABASE_PATH, help='Path to the SQLite database file')
@click.option('--init-db-only', is_flag=True, help='Only initialize the database and exit')
@click.option('--show-stats', is_flag=True, help='Show database statistics and exit')
def main(max_albums: int, skip_existing: bool, db_path: str, init_db_only: bool, show_stats: bool):
    """Main entry point."""
    # Update global database path
    global DATABASE_PATH
    DATABASE_PATH = db_path
    
    # Initialize database
    init_database()
    
    if init_db_only:
        console.print("[green]Database initialized successfully. Exiting.[/green]")
        return
    
    if show_stats:
        scraper = GooglePhotosScraper(max_albums=max_albums, skip_existing=skip_existing)
        scraper.print_database_summary()
        return
    
    # Run the scraper
    async def run_scraper():
        scraper = GooglePhotosScraper(max_albums=max_albums, skip_existing=skip_existing)
        result = await scraper.scrape_albums()
        
        # Print database summary
        scraper.print_database_summary()
    
    asyncio.run(run_scraper())

if __name__ == "__main__":
    main()
