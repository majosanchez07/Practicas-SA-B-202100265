"""
Pruebas del esquema GraphQL del catalogo de libros.

Se ejecutan consultas y mutaciones reales contra el esquema de Strawberry,
respaldado por una base SQLite en memoria (ver conftest.py). No se simulan los
resolvers: se ejercita el mismo codigo que corre en el pod, incluidas las
consultas de SQLAlchemy.
"""
import pytest

from src.graphql.schema import schema


def ejecutar(consulta: str, variables: dict | None = None):
    """
    Ejecuta una operacion GraphQL de forma sincrona y falla la prueba ante
    cualquier error del esquema, para que un fallo del resolver no se confunda
    con un dato faltante.
    """
    resultado = schema.execute_sync(consulta, variable_values=variables)
    assert resultado.errors is None, f'GraphQL devolvio errores: {resultado.errors}'
    return resultado.data


class TestDefinicionDelEsquema:
    """
    El contrato del esquema es lo que consumen el gateway y el frontend. Estas
    pruebas lo fijan sin tocar la base: un cambio accidental de nombre o de
    tipo rompe a los consumidores y debe detectarse aqui.
    """

    def test_expone_las_consultas_esperadas(self):
        definicion = str(schema)
        assert 'books:' in definicion
        assert 'book(' in definicion

    def test_expone_las_mutaciones_esperadas(self):
        definicion = str(schema)
        assert 'createBook(' in definicion
        assert 'updateBookAvailability(' in definicion

    def test_el_tipo_libro_tiene_todos_sus_campos(self):
        definicion = str(schema)
        for campo in ('id:', 'title:', 'author:', 'isbn:', 'genre:', 'available:'):
            assert campo in definicion, f'falta el campo {campo} en BookType'

    def test_genre_es_opcional_y_los_demas_obligatorios(self):
        """
        El modelo declara genre nullable y el resto NOT NULL. El esquema debe
        reflejarlo: "String!" para los obligatorios, "String" para genre.
        """
        definicion = str(schema)
        assert 'title: String!' in definicion
        assert 'author: String!' in definicion
        assert 'isbn: String!' in definicion
        assert 'genre: String\n' in definicion or 'genre: String ' in definicion


class TestConsultaBooks:
    def test_lista_vacia_cuando_no_hay_libros(self, db_en_memoria):
        datos = ejecutar('{ books { id title } }')
        assert datos['books'] == []

    def test_devuelve_todos_los_libros(self, libros_de_ejemplo):
        datos = ejecutar('{ books { id title author } }')
        assert len(datos['books']) == 3

    def test_devuelve_los_campos_correctos(self, libros_de_ejemplo):
        datos = ejecutar('{ books { title author isbn genre available } }')
        titulos = {libro['title'] for libro in datos['books']}
        assert 'Rayuela' in titulos
        rayuela = next(l for l in datos['books'] if l['title'] == 'Rayuela')
        assert rayuela['author'] == 'Julio Cortazar'
        assert rayuela['isbn'] == '978-8437604572'
        assert rayuela['available'] is False


class TestConsultaBook:
    def test_devuelve_el_libro_por_su_id(self, libros_de_ejemplo):
        todos = ejecutar('{ books { id title } }')['books']
        buscado = todos[0]
        datos = ejecutar(
            'query ($id: Int!) { book(id: $id) { id title } }',
            {'id': buscado['id']},
        )
        assert datos['book']['title'] == buscado['title']

    def test_devuelve_null_si_el_id_no_existe(self, libros_de_ejemplo):
        """
        El resolver retorna None y el tipo es Optional, de modo que la
        respuesta correcta es data.book = null y NO un error de GraphQL.
        """
        datos = ejecutar('{ book(id: 99999) { id title } }')
        assert datos['book'] is None


class TestMutacionCreateBook:
    def test_crea_el_libro_y_devuelve_su_id(self, db_en_memoria):
        datos = ejecutar('''
            mutation {
              createBook(title: "Don Quijote", author: "Miguel de Cervantes",
                         isbn: "978-8424116118", genre: "Novela") {
                id title author isbn genre available
              }
            }
        ''')
        creado = datos['createBook']
        assert creado['id'] is not None
        assert creado['title'] == 'Don Quijote'
        assert creado['isbn'] == '978-8424116118'

    def test_el_libro_creado_queda_persistido(self, db_en_memoria):
        """La mutacion hace commit: una consulta posterior debe encontrarlo."""
        ejecutar('''
            mutation {
              createBook(title: "El Aleph", author: "Jorge Luis Borges",
                         isbn: "978-0142437889") { id }
            }
        ''')
        datos = ejecutar('{ books { title } }')
        assert [l['title'] for l in datos['books']] == ['El Aleph']

    def test_un_libro_nuevo_nace_disponible(self, db_en_memoria):
        """
        El modelo declara available con default True. Es la regla de negocio
        que sostiene el flujo de prestamos: un libro recien catalogado se puede
        prestar sin un paso adicional.
        """
        datos = ejecutar('''
            mutation {
              createBook(title: "Pedro Paramo", author: "Juan Rulfo",
                         isbn: "978-6074450798") { available }
            }
        ''')
        assert datos['createBook']['available'] is True

    def test_genre_puede_omitirse(self, db_en_memoria):
        datos = ejecutar('''
            mutation {
              createBook(title: "Sin genero", author: "Anonimo",
                         isbn: "978-0000000001") { genre }
            }
        ''')
        assert datos['createBook']['genre'] is None


class TestMutacionUpdateBookAvailability:
    def test_marca_un_libro_como_no_disponible(self, libros_de_ejemplo):
        """El caso que ejecuta el flujo de prestamo al entregar un ejemplar."""
        libros = ejecutar('{ books { id available } }')['books']
        disponible = next(l for l in libros if l['available'])

        datos = ejecutar(
            'mutation ($id: Int!) { updateBookAvailability(id: $id, available: false) '
            '{ id available } }',
            {'id': disponible['id']},
        )
        assert datos['updateBookAvailability']['available'] is False

    def test_el_cambio_queda_persistido(self, libros_de_ejemplo):
        libros = ejecutar('{ books { id available } }')['books']
        disponible = next(l for l in libros if l['available'])

        ejecutar(
            'mutation ($id: Int!) { updateBookAvailability(id: $id, available: false) { id } }',
            {'id': disponible['id']},
        )
        vueltos_a_leer = ejecutar('{ books { id available } }')['books']
        actualizado = next(l for l in vueltos_a_leer if l['id'] == disponible['id'])
        assert actualizado['available'] is False

    def test_devuelve_un_libro_a_disponible(self, libros_de_ejemplo):
        """El flujo inverso: la devolucion del prestamo."""
        libros = ejecutar('{ books { id available } }')['books']
        prestado = next(l for l in libros if not l['available'])

        datos = ejecutar(
            'mutation ($id: Int!) { updateBookAvailability(id: $id, available: true) '
            '{ available } }',
            {'id': prestado['id']},
        )
        assert datos['updateBookAvailability']['available'] is True

    def test_devuelve_null_si_el_libro_no_existe(self, db_en_memoria):
        datos = ejecutar(
            'mutation { updateBookAvailability(id: 99999, available: false) { id } }'
        )
        assert datos['updateBookAvailability'] is None
