const API_URL = 'http://localhost:8000';

function mostrarMensaje(id, texto, tipo) {
    const el = document.getElementById(id);
    el.textContent = texto;
    el.className = 'mensaje ' + tipo;
}

async function registrar() {
    const nombre = document.getElementById('nombre').value;
    const correo = document.getElementById('correo').value;
    const contrasena = document.getElementById('contrasena').value;
    const rol = document.getElementById('rol').value;

    if (!nombre || !correo || !contrasena) {
        mostrarMensaje('mensaje', 'Todos los campos son obligatorios', 'error');
        return;
    }

    try {
        const response = await fetch(API_URL + '/auth/registro', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({nombre, correo, contrasena, rol})
        });
        const data = await response.json();
        if (response.ok) {
            mostrarMensaje('mensaje', 'Registro exitoso! Redirigiendo...', 'success');
            setTimeout(() => window.location.href = 'login.html', 1500);
        } else {
            mostrarMensaje('mensaje', data.detail || 'Error al registrar', 'error');
        }
    } catch (error) {
        mostrarMensaje('mensaje', 'Error de conexion con el servidor', 'error');
    }
}

async function login() {
    const correo = document.getElementById('correo').value;
    const contrasena = document.getElementById('contrasena').value;

    if (!correo || !contrasena) {
        mostrarMensaje('mensaje', 'Todos los campos son obligatorios', 'error');
        return;
    }

    try {
        const response = await fetch(API_URL + '/auth/login', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            credentials: 'include',
            body: JSON.stringify({correo, contrasena})
        });
        const data = await response.json();
        if (response.ok) {
            sessionStorage.setItem('nombre', data.nombre);
            sessionStorage.setItem('rol', data.rol);
            mostrarMensaje('mensaje', 'Login exitoso! Redirigiendo...', 'success');
            setTimeout(() => window.location.href = 'confirmacion.html', 1500);
        } else {
            mostrarMensaje('mensaje', data.detail || 'Credenciales invalidas', 'error');
        }
    } catch (error) {
        mostrarMensaje('mensaje', 'Error de conexion con el servidor', 'error');
    }
}

async function logout() {
    try {
        await fetch(API_URL + '/auth/logout', {
            method: 'POST',
            credentials: 'include'
        });
    } catch (error) {}
    sessionStorage.clear();
    window.location.href = 'login.html';
}

async function probarRutaAdminCliente() {
    try {
        const response = await fetch(API_URL + '/rutas/admin-cliente', {
            method: 'GET',
            credentials: 'include'
        });
        const data = await response.json();
        if (response.ok) {
            mostrarMensaje('mensaje', 'Ruta Admin+Cliente: Acceso permitido - Rol: ' + data.rol, 'success');
        } else {
            mostrarMensaje('mensaje', data.detail || 'Acceso denegado', 'error');
        }
    } catch (error) {
        mostrarMensaje('mensaje', 'Error de conexion', 'error');
    }
}

async function probarRutaAdmin() {
    try {
        const response = await fetch(API_URL + '/rutas/admin', {
            method: 'GET',
            credentials: 'include'
        });
        const data = await response.json();
        if (response.ok) {
            mostrarMensaje('mensaje', 'Ruta Solo Admin: Acceso permitido - Rol: ' + data.rol, 'success');
        } else {
            mostrarMensaje('mensaje', data.detail || 'Acceso denegado', 'error');
        }
    } catch (error) {
        mostrarMensaje('mensaje', 'Error de conexion', 'error');
    }
}

window.onload = function() {
    const nombre = sessionStorage.getItem('nombre');
    const rol = sessionStorage.getItem('rol');

    if (document.getElementById('nombre-usuario')) {
        document.getElementById('nombre-usuario').textContent = nombre || 'Desconocido';
        const rolEl = document.getElementById('rol-usuario');
        rolEl.textContent = rol || 'Desconocido';
        rolEl.className = rol === 'admin' ? 'badge admin' : 'badge cliente';
    }

    if (document.getElementById('rol-verificado')) {
        document.getElementById('rol-verificado').textContent = rol || 'Desconocido';
    }
}
