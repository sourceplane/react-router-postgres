-- The template's nine books, as its init.sql inserts them (the covers are
-- the Worker's static assets under /images/books).
--
-- Upstream ran this once by hand. As a migration it runs once per database,
-- and ON CONFLICT keeps it a no-op where a book with the same id is already
-- there. The rows carry explicit ids, as upstream's do, so the id sequence is
-- moved past them: a book an owner adds later gets the next free id instead
-- of colliding with these.
INSERT INTO books (id, title, author, description, image_url, genre) VALUES
(1, 'The Brothers Karamazov', 'Fyodor Dostoevsky', 'A passionate philosophical novel set in 19th-century Russia, which explores ethical debates of God, free will, and morality.', '/images/books/brothers-karamazov.jpg', 'Literary Fiction'),
(2, 'East of Eden', 'John Steinbeck', 'A multigenerational family saga set in the Salinas Valley, California, exploring themes of good and evil through the intertwined stories of two families.', '/images/books/east-of-eden.jpg', 'Literary Fiction'),
(3, 'The Fifth Season', 'N.K. Jemisin', 'Set in a world where catastrophic climate change occurs regularly, this novel follows a woman searching for her daughter while navigating a society divided by powers.', '/images/books/fifth-season.jpg', 'Science Fiction & Fantasy'),
(4, 'Jane Eyre', 'Charlotte Brontë', 'A novel about a strong-willed orphan who becomes a governess, falls in love with her employer, and discovers his dark secret.', '/images/books/jane-eyre.jpg', 'Literary Fiction'),
(5, 'Anna Karenina', 'Leo Tolstoy', 'A complex novel of family life among the Russian aristocracy, focusing on an adulterous affair between Anna Karenina and Count Vronsky.', '/images/books/anna-karenina.jpg', 'Literary Fiction'),
(6, 'Giovanni''s Room', 'James Baldwin', 'A groundbreaking novel that follows an American man living in Paris as he grapples with his sexual identity and relationships.', '/images/books/giovannis-room.jpg', 'Historical Fiction'),
(7, 'My Brilliant Friend', 'Elena Ferrante', 'The first novel in the Neapolitan quartet that traces the friendship between Elena and Lila, from their childhood in a poor Naples neighborhood through their diverging paths in life.', '/images/books/my-brilliant-friend.jpg', 'Literary Fiction'),
(8, 'The Remains of the Day', 'Kazuo Ishiguro', 'The story of an English butler reflecting on his life of service and missed opportunities as he takes a road trip through the countryside.', '/images/books/remains-of-the-day.jpg', 'Historical Fiction'),
(9, 'The Left Hand of Darkness', 'Ursula K. Le Guin', 'A science fiction novel that follows an envoy sent to convince the ambisexual people of the planet Gethen to join an interplanetary collective.', '/images/books/left-hand-of-darkness.jpg', 'Science Fiction & Fantasy')
ON CONFLICT (id) DO NOTHING;

SELECT setval(pg_get_serial_sequence('books', 'id'), (SELECT COALESCE(MAX(id), 1) FROM books));
