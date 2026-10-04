use std::ffi::c_void;
use std::ptr;

use anyhow::{Context, Result};
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::System::Memory::{
    CreateFileMappingW, FILE_MAP_WRITE, MEMORY_MAPPED_VIEW_ADDRESS, MapViewOfFile, PAGE_READWRITE,
    UnmapViewOfFile,
};
use windows::core::PCWSTR;

pub struct SharedFrame {
    pub name: String,
    _mapping: HANDLE,
}

impl SharedFrame {
    pub fn create(generation: u64, bytes: &[u8]) -> Result<Self> {
        let name = format!("Local\\MiaotouFrame-{}-{generation}", std::process::id());
        let wide: Vec<u16> = name.encode_utf16().chain(Some(0)).collect();
        let length = u64::try_from(bytes.len()).context("frame is too large")?;
        let mapping = unsafe {
            CreateFileMappingW(
                HANDLE(usize::MAX as *mut c_void),
                None,
                PAGE_READWRITE,
                (length >> 32) as u32,
                length as u32,
                PCWSTR(wide.as_ptr()),
            )
        }?;
        let view = unsafe { MapViewOfFile(mapping, FILE_MAP_WRITE, 0, 0, bytes.len()) };
        if view.Value.is_null() {
            unsafe { CloseHandle(mapping).ok() };
            anyhow::bail!("MapViewOfFile failed");
        }
        unsafe {
            ptr::copy_nonoverlapping(bytes.as_ptr(), view.Value.cast::<u8>(), bytes.len());
            UnmapViewOfFile(MEMORY_MAPPED_VIEW_ADDRESS {
                Value: view.Value.cast::<c_void>(),
            })?;
        }
        Ok(Self {
            name,
            _mapping: mapping,
        })
    }
}

impl Drop for SharedFrame {
    fn drop(&mut self) {
        unsafe { CloseHandle(self._mapping).ok() };
    }
}
