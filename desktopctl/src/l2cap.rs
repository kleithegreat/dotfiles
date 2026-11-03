//! A connected BR/EDR L2CAP channel on tokio; std has no Bluetooth sockets.

use std::{
    io,
    mem::size_of,
    os::fd::{AsRawFd, FromRawFd, OwnedFd},
    time::Duration,
};
use tokio::io::{Interest, unix::AsyncFd};

const BTPROTO_L2CAP: libc::c_int = 0;
const BDADDR_BREDR: u8 = 0;
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

#[repr(C)]
struct SockaddrL2 {
    family: libc::sa_family_t,
    psm: u16,
    bdaddr: [u8; 6],
    cid: u16,
    bdaddr_type: u8,
}

pub struct Channel(AsyncFd<OwnedFd>);

impl Channel {
    pub async fn connect(address: &str, psm: u16) -> io::Result<Self> {
        let address = SockaddrL2 {
            family: libc::AF_BLUETOOTH as libc::sa_family_t,
            psm: psm.to_le(),
            bdaddr: bdaddr(address)?,
            cid: 0,
            bdaddr_type: BDADDR_BREDR,
        };
        let fd = syscall(unsafe {
            libc::socket(
                libc::AF_BLUETOOTH,
                libc::SOCK_SEQPACKET | libc::SOCK_NONBLOCK | libc::SOCK_CLOEXEC,
                BTPROTO_L2CAP,
            )
        })?;
        let fd = unsafe { OwnedFd::from_raw_fd(fd) };
        let started = syscall(unsafe {
            libc::connect(
                fd.as_raw_fd(),
                (&raw const address).cast(),
                size_of::<SockaddrL2>() as libc::socklen_t,
            )
        });
        match started {
            Err(error) if error.raw_os_error() != Some(libc::EINPROGRESS) => return Err(error),
            _ => {}
        }
        // An OwnedFd stays open and unchanged for as long as it is owned.
        let fd = unsafe { AsyncFd::register(fd) }.map_err(|error| error.into_parts().1)?;
        tokio::time::timeout(CONNECT_TIMEOUT, fd.writable())
            .await
            .map_err(|_| io::Error::from(io::ErrorKind::TimedOut))??
            .retain_ready();
        match socket_error(fd.get_ref())? {
            0 => Ok(Self(fd)),
            errno => Err(io::Error::from_raw_os_error(errno)),
        }
    }

    /// One packet; zero bytes is the peer closing the channel.
    pub async fn recv(&self, buffer: &mut [u8]) -> io::Result<usize> {
        self.0
            .async_io(Interest::READABLE, |fd| {
                let read = unsafe {
                    libc::recv(fd.as_raw_fd(), buffer.as_mut_ptr().cast(), buffer.len(), 0)
                };
                syscall(read as libc::c_int).map(|_| read as usize)
            })
            .await
    }

    pub async fn send(&self, packet: &[u8]) -> io::Result<()> {
        self.0
            .async_io(Interest::WRITABLE, |fd| {
                let sent =
                    unsafe { libc::send(fd.as_raw_fd(), packet.as_ptr().cast(), packet.len(), 0) };
                syscall(sent as libc::c_int).map(drop)
            })
            .await
    }
}

fn syscall(result: libc::c_int) -> io::Result<libc::c_int> {
    match result {
        -1 => Err(io::Error::last_os_error()),
        fd => Ok(fd),
    }
}

fn socket_error(fd: &OwnedFd) -> io::Result<libc::c_int> {
    let mut errno: libc::c_int = 0;
    let mut length = size_of::<libc::c_int>() as libc::socklen_t;
    syscall(unsafe {
        libc::getsockopt(
            fd.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_ERROR,
            (&raw mut errno).cast(),
            &mut length,
        )
    })?;
    Ok(errno)
}

/// `AA:BB:CC:DD:EE:FF`, stored least significant byte first.
fn bdaddr(address: &str) -> io::Result<[u8; 6]> {
    let invalid = || crate::invalid_input(format!("not a Bluetooth address: {address}"));
    let mut bytes = [0; 6];
    let mut parts = address.split(':');
    for byte in bytes.iter_mut().rev() {
        *byte = u8::from_str_radix(parts.next().ok_or_else(invalid)?, 16).map_err(|_| invalid())?;
    }
    match parts.next() {
        Some(_) => Err(invalid()),
        None => Ok(bytes),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bdaddr_is_little_endian_and_strict() {
        assert_eq!(
            bdaddr("70:22:FE:95:08:47").expect("address"),
            [0x47, 0x08, 0x95, 0xfe, 0x22, 0x70]
        );
        assert!(bdaddr("70:22:FE:95:08").is_err());
        assert!(bdaddr("70:22:FE:95:08:47:00").is_err());
        assert!(bdaddr("70:22:FE:95:08:ZZ").is_err());
    }
}
