#!/usr/bin/env -S uv run --script

# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "playwright",
#   "rich",
#   "python-dateutil",
# ]
# ///

import asyncio
import time
from datetime import datetime
from pathlib import Path
from dateutil import parser
from rich.console import Console
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError

console = Console()

USER_DATA_DIR = "./brave_playwright_profile2"
BRAVE_EXECUTABLE = "/usr/bin/brave-browser"

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

async def get_text(page, selector: str, timeout: int = 2000, image: int = 0):
    start = time.perf_counter() * 1000
    while time.perf_counter() * 1000 - start < timeout:
        try:
            # Use first() to get the first matching element
            #el = page.locator(selector).first
            #await el.wait_for(timeout=timeout)
            #return await el.inner_text()
            el = await page.query_selector(selector)
            if el:
                return await el.inner_text()
        except PlaywrightTimeoutError:
            console.print(f"[yellow]Timed out waiting for element: {selector}[/yellow]")
        time.sleep(0.05)
    return None

async def get_album_title(page, timeout=2000) -> tuple[int, str]:
    """Wait for the info panel to be visible and return its content."""
    try:
        
        # Extract info from the info panel
        info = {}
        
        # Try to get album title by finding the 'items' text and getting the previous div
        items_div = await page.query_selector('div:text("items")')
        if items_div:
            items = int((await items_div.inner_text()).split(" ")[0])
            album_title_el = await items_div.evaluate_handle('el => el.previousElementSibling')
            if album_title_el:
                album_title = await album_title_el.inner_text()
        return (items, album_title)
        
    except Exception as e:
        console.print(f"[red]Error in wait_for_info_panel: {e}[/red]")



async def wait_for_info_panel(page, timeout=2000, image=0):
    """Wait for the info panel to be visible and return its content."""
    try:
        # Extract info from the info panel
        info = {}
        
        # Try to get album title by finding the 'items' text and getting the previous div
        items_div = await page.query_selector('div:text("items")')
        if items_div:
            album_title_el = await items_div.evaluate_handle('el => el.previousElementSibling')
            if album_title_el:
                info['album_title'] = await album_title_el.inner_text()
            else:
                info['album_title'] = "N/A"
        else:
            info['album_title'] = "N/A"
        
        info['filename'] = await get_text(page, 'div[aria-label*="Filename"]', timeout=timeout, image=image)
        
        # Try to get date
        # Get date and time
        date_text = await get_text(page, 'div[aria-label*="Date taken"]', timeout=timeout, image=image)
        time_el = await page.query_selector('span[aria-label*="Time taken"]')
        time_text = await time_el.inner_text() if time_el else "N/A"
        
        # Parse the date string using dateutil.parser
        try:
            # Combine date and time strings and parse
            date_str = f"{date_text} {time_text}"
            info['date'] = parser.parse(date_str)  # Store datetime object
            info['date_str'] = info['date'].strftime("%d.%m.%y %H:%M")  # Store formatted string
        except Exception as e:
            console.print(f"[yellow]Error parsing date: {e}[/yellow]")
            info['date'] = None
            info['date_str'] = f"{date_text} {time_text}"
        info['shared_by'] = (await get_text(page, 'div:text("Shared by")', timeout=timeout, image=image)).replace("Shared by", "").strip()
        
        return info
    except Exception as e:
        console.print(f"[red]Error in wait_for_info_panel: {e}[/red]")
        return None

async def main():
    Path(USER_DATA_DIR).mkdir(exist_ok=True)
    async with async_playwright() as p:
        context = await p.chromium.launch_persistent_context(
            user_data_dir=USER_DATA_DIR,
            # executable_path=BRAVE_EXECUTABLE,
            headless=False,
            args=STEALTH_ARGS,
            ignore_default_args=["--enable-automation"],
            viewport={"width": 1280, "height": 720},
            slow_mo=40,  # Slow down automation to make it more reliable
        )
        await context.add_init_script(STEALTH_INIT_SCRIPT)

        page = context.pages[0] if context.pages else await context.new_page()
        
        # Set a default timeout for all operations
        page.set_default_timeout(10000)
        
        await page.goto("https://photos.google.com/albums")
        

        image_count = 0
        last_filename = None
        duplicate_count = 0
        

        while True:
            # Check if infos are already visible
            if image_count == 0:
                console.print("[yellow]Please select the next image to continue...[/yellow]")
                try:
                    await page.get_by_text("Details").first.wait_for(timeout=10000)
                    #await get_text(page, 'div:text("Details")', timeout=20000)
                except PlaywrightTimeoutError:
                    console.print("[yellow]Press Enter to continue...[/yellow]")
                    input()
            try:
                if image_count == 0:
                    items, album_title = await get_album_title(page)
                # Wait for the info panel to be visible and get info
                info = await wait_for_info_panel(page, image=image_count)
                if not info:
                    console.print("[yellow]Could not extract info for current image[/yellow]")
                    break
                    
                current_filename = info['filename']
                
                same_filename_again = current_filename == last_filename and current_filename != "N/A"
 
                if not same_filename_again: 
                    last_filename = current_filename
                    image_count += 1
                    
                    console.print(f"\n[bold blue]=== Image {image_count}/{items} ===[/bold blue]")
                    console.print(f"[bold]Album:[/bold] {album_title}")
                    console.print(f"[bold]Filename:[/bold] {current_filename}")
                    console.print(f"[bold]Date:[/bold] {info['date_str']}")
                    # You can access the datetime object later with info['date'] if needed
                    console.print(f"[bold]Shared by:[/bold] {info['shared_by']}")

               
                # Check for duplicate filenames to detect end of album
                if same_filename_again or image_count >= items:
                    duplicate_count += 1
                    if duplicate_count >= 10 or image_count >= items:  # If we see the same filename twice in a row
                        console.print("[yellow]Reached end of album, returning to album view...[/yellow]")
                        # Press Escape twice to exit the current view
                        await page.keyboard.press('Escape')
                        await asyncio.sleep(0.5)
                        await page.keyboard.press('Escape')
                        await asyncio.sleep(1)
                        
                        last_filename = None
                        duplicate_count = 0
                        image_count = 0
                        continue
                else:
                    duplicate_count = 0
                if duplicate_count > 0:
                    console.print(f"[bold]Duplicate count: {duplicate_count}[/bold]")
                # Navigate to next image
                await page.keyboard.press('ArrowRight')
                await asyncio.sleep(0.08)  # Wait for the next image to load

            except PlaywrightTimeoutError:
                console.print("[yellow]Timed out waiting for element. The UI might have changed.[/yellow]")
                break
            except Exception as e:
                console.print(f"[red]Unexpected error: {e}[/red]")
                break

        console.print("\n[bold green]=== Summary ===[/bold green]")
        console.print(f"[green]Processed {image_count} images.[/green]")
        console.print("[blue]You can now close the browser or press Enter to exit...[/blue]")
        input()
        await context.close()

if __name__ == "__main__":
    asyncio.run(main())
